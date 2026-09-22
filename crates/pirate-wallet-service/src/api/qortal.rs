use super::*;
use crate::models::{
    QortalPartialHistory, QortalPartialTransaction, QortalSyncStatus, QortalTransaction,
    QortalTxMetadata,
};
use pirate_storage_sqlite::AddressScope;
use serde_json::{json, Value};
use std::collections::HashMap;

/// Standard Qortal shielded send request.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct QortalSendRequest {
    /// Wallet-owned shielded address whose key group may be selected.
    pub input: String,
    /// Shielded recipients.
    pub output: Vec<Output>,
    /// Fee in arrrtoshis.
    pub fee: Option<u64>,
}

#[derive(Debug, Default)]
struct SyncSession {
    sync_id: u64,
    active: bool,
    start_height: u64,
    target_height: u64,
}

lazy_static::lazy_static! {
    static ref SYNC_SESSIONS: parking_lot::Mutex<HashMap<WalletId, SyncSession>> =
        parking_lot::Mutex::new(HashMap::new());
}

/// Convert unified-core progress into the schema consumed by Qortal Core.
pub fn qortal_sync_status(wallet_id: WalletId) -> Result<QortalSyncStatus> {
    let mut status = sync_status(wallet_id.clone())?;
    if status.local_height == 0 {
        status.local_height = u64::from(get_wallet_meta(&wallet_id)?.birthday_height);
    }
    let mut sessions = SYNC_SESSIONS.lock();
    let session = sessions.entry(wallet_id).or_default();
    Ok(update_sync_session(session, &status))
}

fn update_sync_session(session: &mut SyncSession, status: &SyncStatus) -> QortalSyncStatus {
    let in_progress = status.is_syncing();

    if !in_progress {
        session.active = false;
        return QortalSyncStatus {
            sync_id: session.sync_id,
            in_progress: false,
            last_error: None,
            start_block: None,
            end_block: None,
            synced_blocks: None,
            trial_decryptions_blocks: None,
            txn_scan_blocks: None,
            total_blocks: None,
            batch_num: None,
            batch_total: None,
            scanned_height: Some(status.local_height),
        };
    }

    if !session.active {
        session.sync_id = session.sync_id.saturating_add(1);
        session.start_height = status.local_height;
        session.active = true;
    }
    session.target_height = session.target_height.max(status.target_height);

    let completed = status.local_height.saturating_sub(session.start_height);
    let total = session.target_height.saturating_sub(session.start_height);
    QortalSyncStatus {
        sync_id: session.sync_id,
        in_progress: true,
        last_error: None,
        start_block: Some(session.start_height),
        end_block: Some(session.target_height),
        synced_blocks: Some(completed),
        // The unified scanner decrypts and records transactions in one pipeline.
        // Report the same completed range for both legacy progress counters.
        trial_decryptions_blocks: Some(completed),
        txn_scan_blocks: Some(completed),
        total_blocks: Some(total),
        batch_num: Some(0),
        batch_total: Some(1),
        scanned_height: None,
    }
}

/// Return the legacy Qortal balance object with numeric arrrtoshi values.
pub fn qortal_balance(wallet_id: WalletId) -> Result<Value> {
    let balance = get_balance(wallet_id.clone())?;
    let mut address_balances = list_address_balances(wallet_id, None)?;
    address_balances.sort_by_key(|entry| {
        let pool_order = if entry.address.starts_with("zs")
            || entry.address.starts_with("ztestsapling")
            || entry.address.starts_with("zregtestsapling")
        {
            0
        } else {
            1
        };
        (pool_order, entry.diversifier_index, entry.created_at)
    });
    let z_addresses = address_balances
        .into_iter()
        .map(|entry| {
            json!({
                "address": entry.address,
                "zbalance": entry.balance,
                "verified_zbalance": entry.spendable,
                "spendable_zbalance": entry.spendable,
                "unverified_zbalance": entry.pending,
            })
        })
        .collect::<Vec<_>>();

    Ok(json!({
        "zbalance": balance.total,
        "verified_zbalance": balance.spendable,
        "spendable_zbalance": balance.spendable,
        "unverified_zbalance": balance.pending,
        "tbalance": 0,
        "z_addresses": z_addresses,
        "t_addresses": [],
    }))
}

pub(super) fn resolve_qortal_source_key_id(
    repo: &Repository,
    account_id: i64,
    wallet_id: &WalletId,
    input: &str,
) -> Result<i64> {
    let source = repo
        .get_address_by_string(account_id, input)?
        .ok_or_else(|| {
            anyhow!(
                "Input address {} is not owned by wallet {}",
                input,
                wallet_id
            )
        })?;
    let address_id = source
        .id
        .ok_or_else(|| anyhow!("Input address row id is missing"))?;

    tx_flow::resolve_spend_key_id(repo, account_id, None, Some(&[address_id]))?
        .ok_or_else(|| anyhow!("Input address {} is missing key metadata", input))
}

/// Send using notes owned by the key group selected by Qortal's source address.
pub async fn qortal_send(wallet_id: WalletId, request: QortalSendRequest) -> Result<String> {
    let source_key_id = {
        let (_db, repo) = open_wallet_db_for(&wallet_id)?;
        let secret = repo
            .get_wallet_secret(&wallet_id)?
            .ok_or_else(|| anyhow!("No wallet secret found for {}", wallet_id))?;
        resolve_qortal_source_key_id(&repo, secret.account_id, &wallet_id, &request.input)?
    };

    let key_filter = Some(vec![source_key_id]);
    let pending = build_tx_filtered(
        wallet_id.clone(),
        request.output,
        request.fee,
        key_filter.clone(),
        None,
    )?;
    let signed = sign_tx_filtered(wallet_id.clone(), pending, key_filter, None)?;
    tx_flow::broadcast_tx_for_wallet(wallet_id, signed).await
}

struct LocalQortalTransaction {
    transaction: QortalTransaction,
    should_recover_outgoing: bool,
    fallback_outgoing_value: Option<u64>,
    outgoing_value_estimate: Option<u64>,
    outgoing_before_fee: Option<u64>,
    outgoing_scope_known: bool,
    stored_fee: Option<u64>,
    metadata_complete: bool,
    metadata_error: Option<String>,
}

fn load_qortal_transactions(
    wallet_id: &WalletId,
    limit: Option<u32>,
) -> Result<(Vec<LocalQortalTransaction>, HashMap<String, AddressScope>)> {
    if is_decoy_mode_active() {
        return Ok((Vec::new(), HashMap::new()));
    }

    let (db, repo) = open_wallet_db_for(wallet_id)?;
    let secret = repo
        .get_wallet_secret(wallet_id)?
        .ok_or_else(|| anyhow!("No wallet secret found for {}", wallet_id))?;
    let sync_state = pirate_storage_sqlite::SyncStateStorage::new(&db).load_sync_state()?;
    let current_height = sync_state.local_height.max(sync_state.target_height);
    load_qortal_account_transactions(
        &repo,
        secret.account_id,
        sync_state.local_height,
        current_height,
        limit,
    )
}

fn load_qortal_account_transactions(
    repo: &pirate_storage_sqlite::Repository<'_>,
    account_id: i64,
    local_height: u64,
    current_height: u64,
    limit: Option<u32>,
) -> Result<(Vec<LocalQortalTransaction>, HashMap<String, AddressScope>)> {
    let addresses = repo.get_all_addresses(account_id)?;
    let addresses_by_id = addresses
        .iter()
        .filter_map(|address| address.id.map(|id| (id, address.clone())))
        .collect::<HashMap<_, _>>();
    let scopes_by_address = addresses
        .into_iter()
        .map(|address| (address.address, address.address_scope))
        .collect::<HashMap<_, _>>();

    // Qortal expects exactly one entry per txid and separates change through
    // metadata arrays, so disable the GUI's split-transfer presentation.
    let records = repo.get_transactions_with_options(account_id, None, local_height, 1, false)?;
    let mut transactions = Vec::with_capacity(records.len());

    // Expired, unmined intents are not chain transactions, and the legacy
    // schema has no failed-send state. They must not poison every later list.
    // Only scanned height proves expiry; apply the caller's limit afterwards.
    for record in records
        .into_iter()
        .filter(|record| !record.expired)
        .take(limit.map(|limit| limit as usize).unwrap_or(usize::MAX))
    {
        let txid_bytes = hex::decode(&record.txid)
            .map_err(|err| anyhow!("Invalid stored transaction id: {}", err))?;
        let mut reversed_txid = txid_bytes.clone();
        reversed_txid.reverse();
        let mut notes = repo.get_notes_by_txid(account_id, &txid_bytes)?;
        if notes.is_empty() {
            notes = repo.get_notes_by_txid(account_id, &reversed_txid)?;
        }

        let mut incoming_metadata = Vec::new();
        let mut incoming_metadata_change = Vec::new();
        for note in notes {
            let Ok(value) = u64::try_from(note.value) else {
                continue;
            };
            if value == 0 {
                continue;
            }
            let address = note
                .address_id
                .and_then(|id| addresses_by_id.get(&id))
                .cloned();
            let metadata = QortalTxMetadata {
                address: address
                    .as_ref()
                    .map(|entry| entry.address.clone())
                    .unwrap_or_else(|| "[UNKNOWN]".to_string()),
                value,
                memo: note
                    .memo
                    .as_ref()
                    .and_then(|memo| pirate_sync_lightd::sapling::full_decrypt::decode_memo(memo)),
            };
            if address
                .as_ref()
                .is_some_and(|entry| entry.address_scope == AddressScope::Internal)
            {
                incoming_metadata_change.push(metadata);
            } else {
                incoming_metadata.push(metadata);
            }
        }

        let confirmed = record.height > 0 && current_height >= record.height as u64;
        let block_height = u32::try_from(record.height.max(0)).unwrap_or(u32::MAX);
        transactions.push(LocalQortalTransaction {
            should_recover_outgoing: record.has_outgoing,
            fallback_outgoing_value: record.outgoing_value,
            outgoing_value_estimate: record.outgoing_value_estimate,
            outgoing_before_fee: record.outgoing_before_fee,
            outgoing_scope_known: record.outgoing_scope_known,
            stored_fee: record.stored_fee,
            metadata_complete: !record.has_outgoing,
            metadata_error: None,
            transaction: QortalTransaction {
                block_height,
                datetime: record.timestamp,
                txid: record.txid,
                amount: record.amount,
                fee: record.fee,
                incoming_metadata,
                incoming_metadata_change,
                outgoing_metadata: Vec::new(),
                outgoing_metadata_change: Vec::new(),
                unconfirmed: (!confirmed).then_some(true),
            },
        });
    }

    Ok((transactions, scopes_by_address))
}

struct RecoveredRecipients {
    fee: Option<u64>,
    recipients: Vec<TransactionRecipient>,
    complete: bool,
}

impl From<Vec<TransactionRecipient>> for RecoveredRecipients {
    fn from(recipients: Vec<TransactionRecipient>) -> Self {
        Self {
            fee: None,
            recipients,
            complete: false,
        }
    }
}

async fn recover_qortal_recipients(
    client: &LightClient,
    wallet_id: &WalletId,
    txid: &str,
) -> Result<RecoveredRecipients> {
    let (_endpoint_config, tx_hash_candidates, sapling_ovks, orchard_ovks, tx_height_hint) =
        collect_tx_recovery_context(wallet_id, txid)?;

    let mut last_error = None;
    for tx_hash in tx_hash_candidates {
        match client.get_transaction(&tx_hash).await {
            Ok(raw) => {
                return recover_qortal_recipients_from_raw(
                    &raw,
                    txid,
                    tx_height_hint,
                    &sapling_ovks,
                    &orchard_ovks,
                    address_prefix_network_type(wallet_id)?,
                );
            }
            Err(err) => last_error = Some(err.to_string()),
        }
    }

    Err(anyhow!(
        "Failed to fetch transaction {}: {}",
        txid,
        last_error.unwrap_or_else(|| "not found".to_string())
    ))
}

fn recover_qortal_recipients_from_raw(
    raw: &[u8],
    txid: &str,
    tx_height_hint: Option<u32>,
    sapling_ovks: &[SaplingOutgoingViewingKey],
    orchard_ovks: &[orchard::keys::OutgoingViewingKey],
    network: NetworkType,
) -> Result<RecoveredRecipients> {
    let parsed = read_pirate_transaction(raw)?;
    let raw_id = hex::encode(parsed.txid().as_ref());
    let reversed_id = hex::encode(
        parsed
            .txid()
            .as_ref()
            .iter()
            .rev()
            .copied()
            .collect::<Vec<_>>(),
    );
    if txid != raw_id && txid != reversed_id {
        return Err(anyhow!("Recovered transaction id does not match {}", txid));
    }
    let recipients = payment_disclosure::recover_outgoing_recipients_with_disclosures_from_raw_tx(
        raw,
        tx_height_hint,
        sapling_ovks,
        orchard_ovks,
        network,
    );
    // A nonempty set can omit outputs (missing OVKs, encoding
    // failures, dummy outputs). Only full coverage proves a total.
    let outputs = parsed
        .sapling_bundle()
        .map_or(0, |bundle| bundle.shielded_outputs().len())
        + parsed
            .ironwood_bundle()
            .map_or(0, |bundle| bundle.actions().len());
    let no_transparent_outputs = parsed
        .transparent_bundle()
        .is_none_or(|bundle| bundle.vout.is_empty());
    let supported_pools = parsed.sprout_bundle().is_none() && parsed.orchard_bundle().is_none();
    let complete =
        supported_pools && no_transparent_outputs && outputs > 0 && recipients.len() == outputs;
    // Padding need not decrypt to determine a fee. For fully shielded supported
    // transactions the public value balances establish it without prevouts.
    // This proves only the fee, not input ownership or recipient completeness.
    let fully_shielded = parsed
        .transparent_bundle()
        .is_none_or(|bundle| bundle.vin.is_empty() && bundle.vout.is_empty());
    let fee = if supported_pools && fully_shielded {
        parsed
            .fee_paid::<anyhow::Error, _>(|_| Ok(None))?
            .map(u64::from)
    } else {
        None
    };
    Ok(RecoveredRecipients {
        fee,
        recipients,
        complete,
    })
}

/// Return transaction history with the metadata arrays Qortal actually reads.
pub async fn qortal_list_transactions(
    wallet_id: WalletId,
    limit: Option<u32>,
) -> Result<Vec<QortalTransaction>> {
    legacy_history(load_and_enrich_qortal_transactions(wallet_id, limit).await?)
}

/// Explicit opt-in: retain incomplete rows and separate unknown totals from estimates.
pub async fn qortal_list_transactions_partial(
    wallet_id: WalletId,
    limit: Option<u32>,
) -> Result<QortalPartialHistory> {
    Ok(partial_history(
        load_and_enrich_qortal_transactions(wallet_id, limit).await?,
    ))
}

async fn load_and_enrich_qortal_transactions(
    wallet_id: WalletId,
    limit: Option<u32>,
) -> Result<Vec<LocalQortalTransaction>> {
    let (mut transactions, scopes_by_address) = load_qortal_transactions(&wallet_id, limit)?;
    // Optional remote metadata must not monopolize the single JNI wallet lane.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    let needs_outgoing_recovery = transactions
        .iter()
        .any(|entry| entry.should_recover_outgoing);
    let recovery_client = if needs_outgoing_recovery {
        let endpoint_config = get_lightd_endpoint_config(wallet_id.clone())?;
        let client_config = tunnel::light_client_config_for_endpoint(
            &endpoint_config,
            RetryConfig {
                max_attempts: 1,
                ..RetryConfig::default()
            },
            Duration::from_secs(30),
            Duration::from_secs(60),
        );
        let client = LightClient::with_config(client_config);
        match tokio::time::timeout_at(deadline, client.connect()).await {
            Ok(Ok(())) => Some(client),
            outcome => {
                tracing::warn!(
                    "Could not connect for Qortal transaction metadata recovery: {:?}",
                    outcome
                );
                None
            }
        }
    } else {
        None
    };

    enrich_qortal_transactions(&mut transactions, &scopes_by_address, deadline, |txid| {
        let client = recovery_client.as_ref();
        let wallet_id = &wallet_id;
        async move {
            match client {
                Some(client) => recover_qortal_recipients(client, wallet_id, &txid).await,
                None => Err(anyhow!("lightwalletd is unavailable")),
            }
        }
    })
    .await?;

    Ok(transactions)
}

fn legacy_history(rows: Vec<LocalQortalTransaction>) -> Result<Vec<QortalTransaction>> {
    if let Some(row) = rows.iter().find(|row| !row.metadata_complete) {
        return Err(anyhow!("Qortal transaction metadata unavailable for {}: use the opt-in partial history API to inspect incomplete rows", row.transaction.txid));
    }
    Ok(rows.into_iter().map(|row| row.transaction).collect())
}

fn partial_history(rows: Vec<LocalQortalTransaction>) -> QortalPartialHistory {
    QortalPartialHistory {
        transactions: rows
            .into_iter()
            .map(|row| {
                let outgoing_value = if !row.should_recover_outgoing {
                    Some(0)
                } else if row.metadata_complete {
                    row.fallback_outgoing_value
                } else {
                    None
                };
                let tx = row.transaction;
                QortalPartialTransaction {
                    txid: tx.txid,
                    block_height: tx.block_height,
                    datetime: tx.datetime,
                    unconfirmed: tx.unconfirmed.unwrap_or(false),
                    has_outgoing: row.should_recover_outgoing,
                    outgoing_value,
                    outgoing_value_estimate: if outgoing_value.is_none() {
                        row.outgoing_value_estimate
                    } else {
                        None
                    },
                    fee: row.stored_fee,
                    fee_estimate: (row.should_recover_outgoing && row.stored_fee.is_none())
                        .then_some(pirate_core::fees::DEFAULT_FEE),
                    incoming_metadata: tx.incoming_metadata,
                    incoming_metadata_change: tx.incoming_metadata_change,
                    outgoing_metadata: tx.outgoing_metadata,
                    outgoing_metadata_change: tx.outgoing_metadata_change,
                    metadata_complete: row.metadata_complete,
                    metadata_error: row.metadata_error,
                }
            })
            .collect(),
    }
}

// One deadline covers connection and every transaction, not one timeout per row.
// Dropping a timed-out read cancels its future; no detached recovery keeps the
// native lane occupied after history has been returned.
async fn enrich_qortal_transactions<F, Fut>(
    transactions: &mut [LocalQortalTransaction],
    scopes_by_address: &HashMap<String, AddressScope>,
    deadline: tokio::time::Instant,
    mut recover: F,
) -> Result<()>
where
    F: FnMut(String) -> Fut,
    Fut: std::future::Future<Output = Result<RecoveredRecipients>>,
{
    for entry in transactions {
        if !entry.should_recover_outgoing {
            continue;
        }
        let recovered = if tokio::time::Instant::now() >= deadline {
            Err(anyhow!("Qortal history metadata recovery budget exhausted"))
        } else {
            match tokio::time::timeout_at(deadline, recover(entry.transaction.txid.clone())).await {
                Ok(result) => result,
                Err(_) => Err(anyhow!("Qortal history metadata recovery budget exhausted")),
            }
        };
        if let Ok(recovery) = &recovered {
            if let Some(fee) = recovery.fee {
                if entry.stored_fee.is_some_and(|stored| stored != fee) {
                    tracing::warn!(txid = %entry.transaction.txid, "Raw fee differs from stored history fee");
                    entry.fallback_outgoing_value = None;
                }
                entry.stored_fee = Some(fee);
                entry.transaction.fee = fee;
                entry.outgoing_value_estimate = None;
                if let Some(before_fee) = entry.outgoing_before_fee {
                    entry.fallback_outgoing_value = before_fee.checked_sub(fee);
                }
            }
        }
        match recovered {
            Ok(recovery) if !recovery.recipients.is_empty() => {
                for recipient in recovery.recipients {
                    let metadata = QortalTxMetadata {
                        address: recipient.address.clone(),
                        value: recipient.amount,
                        memo: recipient.memo,
                    };
                    if scopes_by_address.get(&recipient.address) == Some(&AddressScope::Internal) {
                        entry.transaction.outgoing_metadata_change.push(metadata);
                    } else {
                        entry.transaction.outgoing_metadata.push(metadata);
                    }
                }
                let Some(recovered_value) = entry
                    .transaction
                    .outgoing_metadata
                    .iter()
                    .try_fold(0u64, |total, metadata| total.checked_add(metadata.value))
                else {
                    entry.fallback_outgoing_value = None;
                    entry.outgoing_value_estimate = None;
                    entry.metadata_error = Some(format!(
                        "Outgoing metadata overflow for {}",
                        entry.transaction.txid
                    ));
                    continue;
                };
                if entry
                    .outgoing_value_estimate
                    .is_some_and(|estimate| recovered_value > estimate)
                {
                    entry.outgoing_value_estimate = None;
                }
                if recovery.complete && entry.outgoing_scope_known {
                    // Decrypted full coverage outranks local fee/accounting assumptions.
                    if entry
                        .fallback_outgoing_value
                        .is_some_and(|local| local != recovered_value)
                    {
                        tracing::warn!(txid = %entry.transaction.txid, "Recovered recipients differ from local history accounting");
                    }
                    entry.fallback_outgoing_value = Some(recovered_value);
                    entry.metadata_complete = true;
                } else if let Some(local) = entry.fallback_outgoing_value {
                    if let Some(remainder) = local.checked_sub(recovered_value) {
                        if remainder > 0 {
                            entry.transaction.outgoing_metadata.push(QortalTxMetadata {
                                address: "[UNKNOWN]".into(),
                                value: remainder,
                                memo: None,
                            });
                        }
                        entry.metadata_complete = true;
                    } else {
                        // Keep individually recovered outputs, but do not treat
                        // their possibly partial sum or the contradicted local value as a total.
                        tracing::warn!(txid = %entry.transaction.txid, "Partial recovered recipients exceed local history accounting");
                        entry.fallback_outgoing_value = None;
                        entry.outgoing_value_estimate = None;
                    }
                }
                if entry.metadata_complete && entry.transaction.outgoing_metadata.is_empty() {
                    entry.transaction.outgoing_metadata.push(QortalTxMetadata {
                        address: "[UNKNOWN]".into(),
                        value: 0,
                        memo: None,
                    });
                }
                if !entry.metadata_complete {
                    entry.metadata_error = Some(format!(
                        "Outgoing metadata incomplete for {}",
                        entry.transaction.txid
                    ));
                }
                continue;
            }
            Ok(_) => {}
            Err(err) => {
                tracing::warn!(txid = %entry.transaction.txid, "Could not recover Qortal metadata: {}", err);
            }
        }
        if let Some(value) = entry.fallback_outgoing_value {
            entry.transaction.outgoing_metadata.push(QortalTxMetadata {
                address: "[UNKNOWN]".into(),
                value,
                memo: None,
            });
            entry.metadata_complete = true;
        } else {
            entry.metadata_error = Some(format!(
                "Outgoing metadata unavailable for {}",
                entry.transaction.txid
            ));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn outgoing_row() -> LocalQortalTransaction {
        LocalQortalTransaction {
            should_recover_outgoing: true,
            fallback_outgoing_value: Some(100),
            outgoing_value_estimate: None,
            outgoing_before_fee: None,
            outgoing_scope_known: true,
            stored_fee: Some(10),
            metadata_complete: false,
            metadata_error: None,
            transaction: QortalTransaction {
                block_height: 42,
                datetime: 1_700_000_000,
                txid: "00".repeat(32),
                amount: -110,
                fee: 10,
                incoming_metadata: Vec::new(),
                incoming_metadata_change: Vec::new(),
                outgoing_metadata: Vec::new(),
                outgoing_metadata_change: Vec::new(),
                unconfirmed: None,
            },
        }
    }

    #[tokio::test(start_paused = true)]
    async fn history_recovery_shares_one_budget_and_keeps_every_local_row() {
        let mut rows = vec![outgoing_row(), outgoing_row(), outgoing_row()];
        let start = tokio::time::Instant::now();
        let mut attempts = 0;
        enrich_qortal_transactions(
            &mut rows,
            &HashMap::new(),
            start + Duration::from_secs(5),
            |_| {
                attempts += 1;
                async {
                    tokio::time::sleep(Duration::from_secs(3)).await;
                    Ok(vec![TransactionRecipient {
                        address: "zs-known".into(),
                        pool: "sapling".into(),
                        amount: 100,
                        output_index: 0,
                        memo: None,
                        payment_disclosure: None,
                    }]
                    .into())
                }
            },
        )
        .await
        .unwrap();
        assert_eq!(attempts, 2);
        assert_eq!(tokio::time::Instant::now() - start, Duration::from_secs(5));
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].transaction.outgoing_metadata[0].address, "zs-known");
        for row in &rows[1..] {
            assert_eq!(row.transaction.outgoing_metadata[0].address, "[UNKNOWN]");
            assert_eq!(row.transaction.outgoing_metadata[0].value, 100);
            assert_eq!(row.transaction.amount, -110);
            assert_eq!(row.transaction.fee, 10);
        }
    }

    #[tokio::test(start_paused = true)]
    async fn stalled_metadata_is_cancelled_and_expired_budget_skips_requests() {
        let mut rows = vec![outgoing_row(), outgoing_row()];
        let dropped = std::rc::Rc::new(std::cell::Cell::new(false));
        struct Guard(std::rc::Rc<std::cell::Cell<bool>>);
        impl Drop for Guard {
            fn drop(&mut self) {
                self.0.set(true);
            }
        }
        let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
        enrich_qortal_transactions(&mut rows, &HashMap::new(), deadline, |_| {
            let guard = Guard(dropped.clone());
            async move {
                let _guard = guard;
                std::future::pending().await
            }
        })
        .await
        .unwrap();
        assert!(dropped.get());
        assert!(rows
            .iter()
            .all(|row| row.transaction.outgoing_metadata[0].value == 100));
        let mut rows = vec![outgoing_row()];
        enrich_qortal_transactions(&mut rows, &HashMap::new(), deadline, |_| async {
            panic!("Expired connection budget must not start any transaction lookup")
        })
        .await
        .unwrap();
        assert_eq!(
            rows[0].transaction.outgoing_metadata[0].address,
            "[UNKNOWN]"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn expired_intents_do_not_poison_history_or_consume_its_limit() {
        use pirate_storage_sqlite::{
            Account, Database, EncryptionAlgorithm, EncryptionKey, MasterKey, NoteRecord, NoteType,
            Repository,
        };
        let directory = tempfile::tempdir().unwrap();
        let salt = pirate_storage_sqlite::generate_salt();
        let key = EncryptionKey::from_passphrase("test-passphrase", &salt).unwrap();
        let db = Database::open(
            directory.path().join("history.db"),
            &key,
            MasterKey::generate(EncryptionAlgorithm::ChaCha20Poly1305),
        )
        .unwrap();
        let repo = Repository::new(&db);
        let account_id = repo
            .insert_account(&Account {
                id: None,
                name: "history".into(),
                created_at: 1,
            })
            .unwrap();
        let receive_txid = vec![0x11; 32];
        repo.insert_note(&NoteRecord {
            id: None,
            account_id,
            key_id: None,
            note_type: NoteType::Ironwood,
            value: 100,
            nullifier: vec![0x12; 32],
            commitment: vec![0x13; 32],
            spent: false,
            height: 100,
            txid: receive_txid.clone(),
            output_index: 0,
            address_id: None,
            spent_txid: None,
            diversifier: None,
            note: None,
            position: None,
            memo: None,
        })
        .unwrap();
        repo.upsert_transaction(&hex::encode(&receive_txid), 100, 1, 0)
            .unwrap();
        repo.upsert_outgoing_transaction_intent(account_id, &"55".repeat(32), 50, 10, 2, 120)
            .unwrap();
        // An advertised target past expiry is insufficient: retain the pending intent.
        let (before, _) =
            load_qortal_account_transactions(&repo, account_id, 100, 1000, None).unwrap();
        assert_eq!(before.len(), 2);
        assert!(before.iter().any(|row| row.should_recover_outgoing));
        // At the expiry boundary it is still pending.
        assert_eq!(
            load_qortal_account_transactions(&repo, account_id, 120, 1000, None)
                .unwrap()
                .0
                .len(),
            2
        );
        let (mut after, scopes) =
            load_qortal_account_transactions(&repo, account_id, 121, 1000, Some(1)).unwrap();
        assert_eq!(after.len(), 1);
        assert_eq!(after[0].transaction.txid, hex::encode(receive_txid));
        enrich_qortal_transactions(
            &mut after,
            &scopes,
            tokio::time::Instant::now(),
            |_| async { panic!("expired intent must not trigger remote recovery") },
        )
        .await
        .unwrap();
    }

    #[tokio::test(start_paused = true)]
    async fn fallback_uses_accounting_value_not_display_amount_or_fee() {
        for (display, fee, exact) in [
            (-250_000_000, 10_000, 250_000_000),
            (-250_000_000, 10_000, 249_990_000),
            (-10_000, 10_000, 250_000_000),
            (0, 10_000, 0),
            (100, 10_000, 250_000_000),
        ] {
            let mut row = outgoing_row();
            row.transaction.amount = display;
            row.transaction.fee = fee;
            row.fallback_outgoing_value = Some(exact);
            let mut rows = vec![row];
            enrich_qortal_transactions(
                &mut rows,
                &HashMap::new(),
                tokio::time::Instant::now(),
                |_| async { panic!("expired budget must not start recovery") },
            )
            .await
            .unwrap();
            assert_eq!(rows[0].transaction.outgoing_metadata.len(), 1);
            assert_eq!(rows[0].transaction.outgoing_metadata[0].value, exact);
            assert_eq!(rows[0].transaction.fee, fee);
        }
    }

    #[tokio::test(start_paused = true)]
    async fn unknown_value_fails_within_shared_budget_instead_of_becoming_zero() {
        let mut row = outgoing_row();
        row.fallback_outgoing_value = None;
        let mut rows = vec![row];
        let start = tokio::time::Instant::now();
        enrich_qortal_transactions(
            &mut rows,
            &HashMap::new(),
            start + Duration::from_secs(5),
            |_| std::future::pending::<Result<RecoveredRecipients>>(),
        )
        .await
        .unwrap();
        assert!(!rows[0].metadata_complete);
        assert!(rows[0]
            .metadata_error
            .as_ref()
            .unwrap()
            .contains(&rows[0].transaction.txid));
        assert_eq!(tokio::time::Instant::now() - start, Duration::from_secs(5));
        assert!(rows[0].transaction.outgoing_metadata.is_empty());
        let error = legacy_history(rows).unwrap_err();
        assert!(error.to_string().contains(&"00".repeat(32)));
    }

    #[tokio::test(start_paused = true)]
    async fn recovered_internal_only_transfer_does_not_use_intent_total() {
        let mut row = outgoing_row();
        row.fallback_outgoing_value = None;
        let mut rows = vec![row];
        let scopes = HashMap::from([("zs-internal".to_string(), AddressScope::Internal)]);
        enrich_qortal_transactions(
            &mut rows,
            &scopes,
            tokio::time::Instant::now() + Duration::from_secs(5),
            |_| async {
                Ok(RecoveredRecipients {
                    fee: None,
                    complete: true,
                    recipients: vec![TransactionRecipient {
                        address: "zs-internal".into(),
                        pool: "sapling".into(),
                        amount: 100,
                        output_index: 0,
                        memo: None,
                        payment_disclosure: None,
                    }],
                })
            },
        )
        .await
        .unwrap();
        assert_eq!(rows[0].transaction.outgoing_metadata_change[0].value, 100);
        assert_eq!(rows[0].transaction.outgoing_metadata.len(), 1);
        assert_eq!(rows[0].transaction.outgoing_metadata[0].value, 0);
    }

    #[tokio::test(start_paused = true)]
    async fn partial_recovery_is_reconciled_with_local_accounting() {
        for value in [40, 100, 101] {
            let mut rows = vec![outgoing_row()];
            let result = enrich_qortal_transactions(
                &mut rows,
                &HashMap::new(),
                tokio::time::Instant::now() + Duration::from_secs(5),
                |_| async {
                    Ok(vec![TransactionRecipient {
                        address: "zs-external".into(),
                        pool: "sapling".into(),
                        amount: value,
                        output_index: 0,
                        memo: None,
                        payment_disclosure: None,
                    }]
                    .into())
                },
            )
            .await;
            if value > 100 {
                result.unwrap();
                assert!(!rows[0].metadata_complete);
                assert_eq!(rows[0].transaction.outgoing_metadata[0].value, 101);
                assert_eq!(rows[0].fallback_outgoing_value, None);
                assert!(legacy_history(rows).is_err());
            } else {
                result.unwrap();
                assert_eq!(
                    rows[0]
                        .transaction
                        .outgoing_metadata
                        .iter()
                        .map(|row| row.value)
                        .sum::<u64>(),
                    100
                );
                if value < 100 {
                    assert_eq!(
                        rows[0].transaction.outgoing_metadata[1].address,
                        "[UNKNOWN]"
                    );
                    assert_eq!(rows[0].transaction.outgoing_metadata[1].value, 60);
                }
            }
        }
    }

    #[tokio::test(start_paused = true)]
    async fn incoming_only_history_never_recovers_outgoing_metadata() {
        let mut row = outgoing_row();
        row.should_recover_outgoing = false;
        row.metadata_complete = true;
        row.fallback_outgoing_value = None;
        let mut rows = vec![row];
        enrich_qortal_transactions(
            &mut rows,
            &HashMap::new(),
            tokio::time::Instant::now(),
            |_| async { panic!("incoming row must not query the network") },
        )
        .await
        .unwrap();
        assert!(rows[0].transaction.outgoing_metadata.is_empty());
    }

    #[tokio::test(start_paused = true)]
    async fn partial_history_keeps_unknown_and_known_rows_without_promoting_estimates() {
        let mut restored = outgoing_row();
        restored.transaction.txid = "11".repeat(32);
        restored.fallback_outgoing_value = None;
        restored.outgoing_value_estimate = Some(90);
        restored.stored_fee = None;
        let mut pending = outgoing_row();
        pending.transaction.txid = "22".repeat(32);
        pending.transaction.unconfirmed = Some(true);
        pending.fallback_outgoing_value = None;
        let mut rows = vec![restored, pending, outgoing_row()];
        let start = tokio::time::Instant::now();
        enrich_qortal_transactions(
            &mut rows,
            &HashMap::new(),
            start + Duration::from_secs(5),
            |_| std::future::pending::<Result<RecoveredRecipients>>(),
        )
        .await
        .unwrap();
        assert_eq!(tokio::time::Instant::now() - start, Duration::from_secs(5));
        let json = serde_json::to_value(partial_history(rows)).unwrap();
        let rows = json["transactions"].as_array().unwrap();
        assert_eq!(rows.len(), 3);
        assert!(rows[0]["outgoing_value"].is_null());
        assert_eq!(rows[0]["outgoing_value_estimate"], "90");
        assert!(rows[0]["fee"].is_null());
        assert_eq!(
            rows[0]["fee_estimate"],
            pirate_core::fees::DEFAULT_FEE.to_string()
        );
        assert_eq!(rows[0]["outgoing_metadata"], serde_json::json!([]));
        assert!(rows[1]["outgoing_value"].is_null());
        assert!(rows[1]["outgoing_value_estimate"].is_null());
        assert_eq!(rows[2]["outgoing_value"], "100");
        assert!(rows[2]["metadata_complete"].as_bool().unwrap());
        assert!(rows[2]["metadata_error"].is_null());
    }

    #[tokio::test(start_paused = true)]
    async fn recovered_coverage_controls_whether_local_disagreement_can_be_resolved() {
        for complete in [false, true] {
            for internal in [false, true] {
                let mut row = outgoing_row();
                row.fallback_outgoing_value = if internal { None } else { Some(100) };
                let mut rows = vec![row];
                let scopes = if internal {
                    HashMap::from([("recipient".to_string(), AddressScope::Internal)])
                } else {
                    HashMap::new()
                };
                enrich_qortal_transactions(
                    &mut rows,
                    &scopes,
                    tokio::time::Instant::now() + Duration::from_secs(5),
                    |_| async {
                        Ok(RecoveredRecipients {
                            fee: None,
                            complete,
                            recipients: vec![TransactionRecipient {
                                address: "recipient".into(),
                                pool: "sapling".into(),
                                amount: 101,
                                output_index: 0,
                                memo: None,
                                payment_disclosure: None,
                            }],
                        })
                    },
                )
                .await
                .unwrap();
                let history = partial_history(rows);
                let row = &history.transactions[0];
                assert_eq!(row.metadata_complete, complete);
                assert_eq!(
                    row.outgoing_value,
                    complete.then_some(if internal { 0 } else { 101 })
                );
                assert_eq!(row.metadata_error.is_none(), complete);
            }
        }
    }

    #[tokio::test(start_paused = true)]
    async fn complete_recovery_cannot_resolve_missing_local_change_scope() {
        let mut row = outgoing_row();
        row.fallback_outgoing_value = None;
        row.outgoing_scope_known = false;
        let mut rows = vec![row];
        enrich_qortal_transactions(
            &mut rows,
            &HashMap::new(),
            tokio::time::Instant::now() + Duration::from_secs(5),
            |_| async {
                Ok(RecoveredRecipients {
                    fee: None,
                    complete: true,
                    recipients: vec![TransactionRecipient {
                        address: "unattributed-change".into(),
                        pool: "sapling".into(),
                        amount: 101,
                        output_index: 0,
                        memo: None,
                        payment_disclosure: None,
                    }],
                })
            },
        )
        .await
        .unwrap();
        let history = partial_history(rows);
        assert_eq!(history.transactions[0].outgoing_value, None);
        assert!(!history.transactions[0].metadata_complete);
        assert_eq!(history.transactions[0].outgoing_metadata[0].value, 101);
    }

    #[test]
    fn raw_recovery_verifies_identity_and_requires_all_outputs() {
        let ovk = SaplingOutgoingViewingKey([77; 32]);
        let (txid, raw) = payment_disclosure::persistence_tests::encrypted_sapling_fixture(ovk);
        let recovered = recover_qortal_recipients_from_raw(
            &raw,
            &txid,
            Some(1_000_000),
            &[ovk],
            &[],
            NetworkType::Mainnet,
        )
        .unwrap();
        assert!(recovered.complete);
        assert_eq!(recovered.recipients.len(), 1);
        assert_eq!(recovered.recipients[0].amount, 100);
        let (mixed_txid, mixed_raw) = payment_disclosure::persistence_tests::encrypted_sapling_fixture_with_transparent_output(ovk, true);
        let mixed = recover_qortal_recipients_from_raw(
            &mixed_raw,
            &mixed_txid,
            Some(1_000_000),
            &[ovk],
            &[],
            NetworkType::Mainnet,
        )
        .unwrap();
        assert_eq!(mixed.recipients.len(), 1);
        assert!(!mixed.complete);
        let missing_keys = recover_qortal_recipients_from_raw(
            &raw,
            &txid,
            Some(1_000_000),
            &[SaplingOutgoingViewingKey([78; 32])],
            &[],
            NetworkType::Mainnet,
        )
        .unwrap();
        assert!(!missing_keys.complete);
        assert!(missing_keys.recipients.is_empty());
        assert!(recover_qortal_recipients_from_raw(
            &raw,
            &"00".repeat(32),
            Some(1_000_000),
            &[ovk],
            &[],
            NetworkType::Mainnet
        )
        .is_err());
    }

    #[tokio::test(start_paused = true)]
    async fn padded_restored_history_uses_raw_fee_without_guessing_missing_outputs() {
        use payment_disclosure::persistence_tests::encrypted_sapling_history_fixture;
        let ovk = SaplingOutgoingViewingKey([77; 32]);
        // Zero-valued unrecoverable padding and a genuinely missing positive
        // recipient must remain distinguishable through local accounting.
        for (hidden, fee) in [(0, 10), (50, 10), (0, 11), (0, 20)] {
            let (txid, raw) =
                encrypted_sapling_history_fixture(ovk, false, false, fee, Some((None, hidden)));
            let mut row = outgoing_row();
            row.transaction.txid = txid.clone();
            row.fallback_outgoing_value = None;
            row.stored_fee = None;
            row.outgoing_before_fee = Some(100 + hidden + fee as u64);
            let mut rows = vec![row];
            enrich_qortal_transactions(
                &mut rows,
                &HashMap::new(),
                tokio::time::Instant::now() + Duration::from_secs(5),
                |_| async {
                    let recovered = recover_qortal_recipients_from_raw(
                        &raw,
                        &txid,
                        Some(1_000_000),
                        &[ovk],
                        &[],
                        NetworkType::Mainnet,
                    )?;
                    assert!(!recovered.complete);
                    assert_eq!(recovered.recipients.len(), 1);
                    Ok(recovered)
                },
            )
            .await
            .unwrap();
            assert!(rows[0].metadata_complete);
            assert_eq!(rows[0].fallback_outgoing_value, Some(100 + hidden));
            assert_eq!(rows[0].stored_fee, Some(fee as u64));
            let legacy = legacy_history(rows).unwrap();
            assert_eq!(
                legacy[0]
                    .outgoing_metadata
                    .iter()
                    .map(|item| item.value)
                    .sum::<u64>(),
                100 + hidden
            );
            if hidden > 0 {
                assert_eq!(legacy[0].outgoing_metadata[1].address, "[UNKNOWN]");
            }
        }
    }

    #[tokio::test(start_paused = true)]
    async fn raw_fee_supersedes_conflicting_stored_fee_without_reusing_its_total() {
        for before_fee in [None, Some(120)] {
            let mut row = outgoing_row();
            row.outgoing_before_fee = before_fee;
            let mut rows = vec![row];
            enrich_qortal_transactions(
                &mut rows,
                &HashMap::new(),
                tokio::time::Instant::now() + Duration::from_secs(5),
                |_| async {
                    Ok(RecoveredRecipients {
                        fee: Some(20),
                        complete: false,
                        recipients: vec![],
                    })
                },
            )
            .await
            .unwrap();
            assert_eq!(rows[0].stored_fee, Some(20));
            assert_eq!(rows[0].transaction.fee, 20);
            assert_eq!(
                rows[0].fallback_outgoing_value,
                before_fee.map(|value| value - 20)
            );
            assert_eq!(rows[0].metadata_complete, before_fee.is_some());
        }
    }

    #[test]
    fn raw_fee_requires_no_transparent_inputs_and_valid_value_balance() {
        use payment_disclosure::persistence_tests::encrypted_sapling_history_fixture;
        let ovk = SaplingOutgoingViewingKey([77; 32]);
        for (vin, vout) in [(true, false), (false, true)] {
            let (txid, raw) = encrypted_sapling_history_fixture(ovk, vout, vin, 10, None);
            let recovered = recover_qortal_recipients_from_raw(
                &raw,
                &txid,
                Some(1_000_000),
                &[ovk],
                &[],
                NetworkType::Mainnet,
            )
            .unwrap();
            assert_eq!(recovered.fee, None);
        }
        let (txid, raw) = encrypted_sapling_history_fixture(ovk, false, false, -1, None);
        assert!(recover_qortal_recipients_from_raw(
            &raw,
            &txid,
            Some(1_000_000),
            &[ovk],
            &[],
            NetworkType::Mainnet
        )
        .is_err());
    }

    #[tokio::test(start_paused = true)]
    async fn padded_pending_send_remains_visible_with_unknown_total() {
        use payment_disclosure::persistence_tests::encrypted_sapling_history_fixture;
        let ovk = SaplingOutgoingViewingKey([77; 32]);
        let (txid, raw) = encrypted_sapling_history_fixture(ovk, false, false, 10, Some((None, 0)));
        let mut row = outgoing_row();
        row.transaction.txid = txid.clone();
        row.transaction.unconfirmed = Some(true);
        row.transaction.block_height = 0;
        row.fallback_outgoing_value = None;
        row.outgoing_scope_known = false;
        let mut rows = vec![row];
        enrich_qortal_transactions(
            &mut rows,
            &HashMap::new(),
            tokio::time::Instant::now() + Duration::from_secs(5),
            |_| async {
                recover_qortal_recipients_from_raw(
                    &raw,
                    &txid,
                    Some(1_000_000),
                    &[ovk],
                    &[],
                    NetworkType::Mainnet,
                )
            },
        )
        .await
        .unwrap();
        let response = partial_history(rows);
        assert_eq!(response.transactions.len(), 1);
        assert!(response.transactions[0].unconfirmed);
        assert_eq!(response.transactions[0].outgoing_value, None);
        assert_eq!(response.transactions[0].outgoing_metadata[0].value, 100);
    }

    #[test]
    fn ironwood_builder_padding_is_not_claimed_as_complete_recovery() {
        use orchard::{
            builder::{Builder, BundleType},
            bundle::BundleVersion,
            value::NoteValue,
            Anchor,
        };
        use zcash_primitives::transaction::{Authorized, TransactionData};
        use zcash_protocol::{
            consensus::{BlockHeight, BranchId},
            value::ZatBalance,
        };
        let key = pirate_core::keys::IronwoodExtendedSpendingKey::master(&[8; 32]).unwrap();
        let recipient = key.to_extended_fvk().address_at(0);
        let ovk = orchard::keys::OutgoingViewingKey::from([77; 32]);
        let version = BundleVersion::ironwood_v3();
        let mut builder = Builder::new(
            BundleType::DEFAULT,
            version,
            version.default_flags(),
            Anchor::empty_tree(),
        )
        .unwrap();
        builder
            .add_output(
                Some(ovk.clone()),
                recipient.inner,
                NoteValue::from_raw(40_000),
                [0; 512],
            )
            .unwrap();
        let (bundle, _) = builder
            .build::<ZatBalance>(&mut rand::rngs::OsRng)
            .unwrap()
            .unwrap();
        assert!(bundle.actions().len() > 1);
        let signed = bundle
            .create_proof(
                &pirate_core::ironwood_params().proving_key,
                &mut rand::rngs::OsRng,
            )
            .unwrap()
            .apply_signatures(rand::rngs::OsRng, [0; 32], &[])
            .unwrap();
        // Real builder padding/encryption/proof; synthetic authorization/prevout,
        // never a transaction to broadcast. Transparent input prevents fee inference.
        let transparent = zcash_transparent::bundle::Bundle {
            vin: vec![zcash_transparent::bundle::TxIn::from_parts(
                zcash_transparent::bundle::OutPoint::new([1; 32], 0),
                zcash_transparent::address::Script::default(),
                u32::MAX,
            )],
            vout: vec![],
            authorization: zcash_transparent::bundle::Authorized,
        };
        let tx = TransactionData::<Authorized>::from_parts_v6(
            BranchId::Nu6_3,
            0,
            BlockHeight::from_u32(5_000_000),
            Some(transparent),
            None,
            None,
            Some(signed.clone()),
        )
        .freeze()
        .unwrap();
        let mut raw = Vec::new();
        tx.write(&mut raw).unwrap();
        let recovery = recover_qortal_recipients_from_raw(
            &raw,
            &tx.txid().to_string(),
            Some(4_000_000),
            &[],
            &[ovk],
            NetworkType::Mainnet,
        )
        .unwrap();
        assert_eq!(recovery.recipients.len(), 1);
        assert_eq!(recovery.recipients[0].amount, 40_000);
        assert!(!recovery.complete);
        assert_eq!(recovery.fee, None);
        // A cross-pool fixture exercises a negative Ironwood value balance
        // offset by Sapling, with no transparent prevouts needed for the fee.
        let (_, sapling_raw) =
            payment_disclosure::persistence_tests::encrypted_sapling_history_fixture(
                SaplingOutgoingViewingKey([77; 32]),
                false,
                false,
                40_010,
                None,
            );
        let sapling_tx = read_pirate_transaction(&sapling_raw).unwrap();
        let shielded = TransactionData::<Authorized>::from_parts_v6(
            BranchId::Nu6_3,
            0,
            BlockHeight::from_u32(5_000_000),
            None,
            sapling_tx.sapling_bundle().cloned(),
            None,
            Some(signed),
        )
        .freeze()
        .unwrap();
        let mut raw = Vec::new();
        shielded.write(&mut raw).unwrap();
        let recovery = recover_qortal_recipients_from_raw(
            &raw,
            &shielded.txid().to_string(),
            Some(1_000_000),
            &[SaplingOutgoingViewingKey([77; 32])],
            &[orchard::keys::OutgoingViewingKey::from([77; 32])],
            NetworkType::Mainnet,
        )
        .unwrap();
        assert_eq!(recovery.fee, Some(10));
        assert_eq!(
            recovery
                .recipients
                .iter()
                .map(|recipient| recipient.amount)
                .sum::<u64>(),
            40_100
        );
        assert!(!recovery.complete);
    }

    #[test]
    fn partial_history_requires_explicit_request_method() {
        let request: crate::service::WalletServiceRequest =
            serde_json::from_value(serde_json::json!({
                "method": "qortal_list_transactions_partial", "wallet_id": "test", "limit": 10
            }))
            .unwrap();
        assert!(matches!(
            request,
            crate::service::WalletServiceRequest::QortalListTransactionsPartial {
                limit: Some(10),
                ..
            }
        ));
    }

    #[test]
    fn qortal_transaction_omits_unconfirmed_when_confirmed() {
        let transaction = QortalTransaction {
            block_height: 42,
            datetime: 1_700_000_000,
            txid: "00".repeat(32),
            amount: 25,
            fee: 0,
            incoming_metadata: vec![QortalTxMetadata {
                address: "zs1example".to_string(),
                value: 25,
                memo: None,
            }],
            incoming_metadata_change: Vec::new(),
            outgoing_metadata: Vec::new(),
            outgoing_metadata_change: Vec::new(),
            unconfirmed: None,
        };

        let encoded = serde_json::to_value(transaction).unwrap();
        assert!(encoded.get("unconfirmed").is_none());
        assert_eq!(encoded["incoming_metadata"][0]["value"], 25);
    }

    #[test]
    fn sync_session_uses_numeric_ids_and_relative_progress() {
        let mut session = SyncSession::default();
        let mut status = SyncStatus {
            local_height: 100,
            target_height: 200,
            percent: 50.0,
            eta: None,
            stage: SyncStage::Notes,
            last_checkpoint: None,
            blocks_per_second: 0.0,
            notes_decrypted: 0,
            last_batch_ms: 0,
        };

        let first = update_sync_session(&mut session, &status);
        assert_eq!(first.sync_id, 1);
        assert_eq!(first.start_block, Some(100));
        assert_eq!(first.synced_blocks, Some(0));
        assert_eq!(first.total_blocks, Some(100));

        status.local_height = 140;
        let progress = update_sync_session(&mut session, &status);
        assert_eq!(progress.sync_id, 1);
        assert_eq!(progress.synced_blocks, Some(40));
        assert_eq!(progress.trial_decryptions_blocks, Some(40));
        assert_eq!(progress.txn_scan_blocks, Some(40));

        status.local_height = 200;
        let idle = update_sync_session(&mut session, &status);
        assert!(!idle.in_progress);
        assert_eq!(idle.scanned_height, Some(200));
        assert!(idle.start_block.is_none());

        status.local_height = 200;
        status.target_height = 250;
        let next = update_sync_session(&mut session, &status);
        assert_eq!(next.sync_id, 2);
    }
}
