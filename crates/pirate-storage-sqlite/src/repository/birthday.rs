use super::*;

impl Repository<'_> {
    /// Retain earlier history even when the caller read the key before another
    /// connection lowered its birthday. No encrypted key material is rewritten.
    pub fn lower_account_key_birthday(&self, key_id: i64, birthday_height: u32) -> Result<()> {
        self.db.conn().execute(
            "UPDATE account_keys SET birthday_height = MIN(birthday_height, ?1) WHERE id = ?2",
            params![i64::from(birthday_height), key_id],
        )?;
        Ok(())
    }

    /// Repair birthdays overwritten by older clients after an earlier rescan.
    ///
    /// A confirmed note establishes that its key's history starts no later than
    /// that note. Correct metadata only; spending still requires normal scan
    /// coverage and witness validation. Encrypted note metadata is inspected
    /// once per account, rather than on every spendability poll.
    pub fn ensure_note_birthday_recovery_migration(&self, account_id: i64) -> Result<()> {
        let marker = format!("note_birthday_recovery_v1:{account_id}");
        let applied = || -> Result<bool> {
            Ok(self
                .db
                .conn()
                .query_row(
                    "SELECT 1 FROM migration_state WHERE key = ?1",
                    [&marker],
                    |_| Ok(()),
                )
                .optional()?
                .is_some())
        };
        if applied()? {
            return Ok(());
        }

        let tx = self.db.unchecked_immediate_transaction()?;
        // Another connection may have finished recovery while we waited.
        if applied()? {
            return Ok(());
        }
        // Read only public key metadata: recovery needs no spending-key unlock.
        let mut keys = tx
            .prepare("SELECT id, birthday_height FROM account_keys WHERE account_id = ?1")?
            .query_map([account_id], |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?))
            })?
            .collect::<std::result::Result<HashMap<_, _>, _>>()?;
        if keys.is_empty() {
            // Legacy wallets create their primary key during sync attachment.
            // Leave recovery pending until that key actually exists.
            return Ok(());
        }
        let original_birthdays = keys.clone();
        // Older clients ignored zero (unknown) birthdays when taking the
        // account minimum. That also requires revalidation if it hid history.
        let previous_floor = keys
            .values()
            .copied()
            .filter(|height| *height > 0)
            .min()
            .unwrap_or(0);
        let mut repaired_from: Option<i64> = None;
        let rows = tx
            .prepare("SELECT account_id, height, key_id FROM notes")?
            .query_map([], |row| {
                Ok((
                    row.get::<_, Vec<u8>>(0)?,
                    row.get::<_, Vec<u8>>(1)?,
                    row.get::<_, Option<Vec<u8>>>(2)?,
                ))
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        for (encrypted_account, encrypted_height, encrypted_key) in rows {
            if self.decrypt_int64(&encrypted_account)? != account_id {
                continue;
            }
            let height = self.decrypt_int64(&encrypted_height)?;
            if height <= 0 {
                continue; // Pending outputs do not establish a mined birthday.
            }
            if height < previous_floor {
                repaired_from = Some(repaired_from.map_or(height, |from| from.min(height)));
            }
            let owner = self.decrypt_optional_int64(encrypted_key)?;
            if let Some(birthday) = owner.and_then(|id| keys.get_mut(&id)) {
                *birthday = (*birthday).min(height);
            } else {
                // Legacy notes may lack ownership metadata. Conservatively
                // retain history for this account without guessing ownership.
                for birthday in keys.values_mut() {
                    *birthday = (*birthday).min(height);
                }
            }
        }

        let mut repaired_keys = 0;
        for (id, birthday) in keys {
            if birthday == original_birthdays[&id] {
                continue;
            }
            tx.execute(
                "UPDATE account_keys SET birthday_height = ?1 WHERE id = ?2",
                params![birthday, id],
            )?;
            repaired_from = Some(repaired_from.map_or(birthday, |from| from.min(birthday)));
            repaired_keys += 1;
        }
        if let Some(from) = repaired_from {
            // The old READY result may have checked zero notes. Latch recovery
            // atomically with the birthday correction, preserving rescan/import
            // obligations. Only the ordinary sync validator can release it.
            let changed = tx.execute(
                "UPDATE spendability_state SET spendable = 0, repair_queued = 1,
                 repair_from_height = CASE
                   WHEN repair_from_height > 0 AND repair_from_height < ?1
                   THEN repair_from_height ELSE ?1 END,
                 reason_code = CASE WHEN rescan_required = 1 OR required_rescan_from_height > 0
                   THEN reason_code ELSE 'ERR_WITNESS_REPAIR_QUEUED' END,
                 updated_at = ?2 WHERE id = 1",
                params![from, chrono::Utc::now().to_rfc3339()],
            )?;
            if changed != 1 {
                return Err(Error::Storage(
                    "Spendability state row is unavailable".into(),
                ));
            }
        }
        tx.execute(
            "INSERT INTO migration_state (key, value, updated_at) VALUES (?1, '1', ?2)",
            params![marker, chrono::Utc::now().to_rfc3339()],
        )?;
        tx.commit()?;
        if let Some(from) = repaired_from {
            pirate_core::debug_log::append_line_fmt(format_args!(
                r#"{{"id":"log_note_birthday_recovery","timestamp":{},"message":"Corrected note history floor; validation pending","data":{{"repaired_keys":{},"recovery_height":{}}}}}"#,
                chrono::Utc::now().timestamp_millis(),
                repaired_keys,
                from,
            ));
        }
        Ok(())
    }
}
