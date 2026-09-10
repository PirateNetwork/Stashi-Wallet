//! Authenticated, encrypted transaction disclosure bundles.

use super::*;
use serde::{Deserialize, Serialize};
use zeroize::Zeroizing;

#[derive(Serialize, Deserialize)]
struct DisclosureEnvelope {
    version: u32,
    wallet_id: String,
    network: String,
    txid: String,
    payload: Vec<u8>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{EncryptionAlgorithm, EncryptionKey};

    #[test]
    fn disclosure_storage_survives_reopen_and_rejects_cross_scope_and_tampering() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("wallet.db");
        let key = EncryptionKey::from_passphrase("test-only", &[7; 32]).unwrap();
        let master =
            || MasterKey::from_bytes(&[9; 32], EncryptionAlgorithm::ChaCha20Poly1305).unwrap();
        let proof = b"private-disclosure-address-amount-and-memo";
        {
            let db = Database::open(&path, &key, master()).unwrap();
            let repo = Repository::new(&db);
            repo.put_payment_disclosures("wallet-a", "mainnet", "tx-a", proof)
                .unwrap();
            let encrypted: Vec<u8> = db
                .conn()
                .query_row("SELECT payload FROM payment_disclosures", [], |row| {
                    row.get(0)
                })
                .unwrap();
            assert!(!encrypted.windows(proof.len()).any(|window| window == proof));
            assert_eq!(
                repo.get_payment_disclosures("wallet-b", "mainnet", "tx-a")
                    .unwrap(),
                None
            );
            assert_eq!(
                repo.get_payment_disclosures("wallet-a", "testnet", "tx-a")
                    .unwrap(),
                None
            );
            assert_eq!(
                repo.get_payment_disclosures("wallet-a", "mainnet", "tx-b")
                    .unwrap(),
                None
            );
        }
        let db = Database::open(&path, &key, master()).unwrap();
        let repo = Repository::new(&db);
        assert_eq!(
            repo.get_payment_disclosures("wallet-a", "mainnet", "tx-a")
                .unwrap()
                .unwrap(),
            proof
        );
        // The last successful bundle is replaced as one atomic SQL write.
        repo.put_payment_disclosures("wallet-a", "mainnet", "tx-a", b"updated")
            .unwrap();
        assert_eq!(
            repo.get_payment_disclosures("wallet-a", "mainnet", "tx-a")
                .unwrap()
                .unwrap(),
            b"updated"
        );
        db.conn().execute(
            "INSERT INTO payment_disclosures SELECT 'wallet-b', network, txid, payload FROM payment_disclosures WHERE wallet_id = 'wallet-a'", [],
        ).unwrap();
        assert!(repo
            .get_payment_disclosures("wallet-b", "mainnet", "tx-a")
            .is_err());
        db.conn()
            .execute(
                "UPDATE payment_disclosures SET payload = X'000102' WHERE wallet_id = 'wallet-a'",
                [],
            )
            .unwrap();
        assert!(repo
            .get_payment_disclosures("wallet-a", "mainnet", "tx-a")
            .is_err());
    }

    #[test]
    fn disclosure_migration_upgrades_v41_without_touching_transactions() {
        let directory = tempfile::tempdir().unwrap();
        let key = EncryptionKey::from_passphrase("test-only", &[7; 32]).unwrap();
        let db = Database::open(
            directory.path().join("wallet.db"),
            &key,
            MasterKey::generate(EncryptionAlgorithm::ChaCha20Poly1305),
        )
        .unwrap();
        db.conn().execute_batch(
            "DROP TABLE payment_disclosures;
             DELETE FROM schema_version WHERE version > 41;
             INSERT OR IGNORE INTO schema_version (version) VALUES (41);
             INSERT INTO transactions (txid, height, timestamp, fee) VALUES ('existing', 123, 456, 10000);",
        ).unwrap();
        crate::migrations::run_migrations(db.conn()).unwrap();
        crate::migrations::run_migrations(db.conn()).unwrap();
        let height: i64 = db
            .conn()
            .query_row(
                "SELECT height FROM transactions WHERE txid = 'existing'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(height, 123);
        assert_eq!(
            Repository::new(&db)
                .get_payment_disclosures("a", "mainnet", "tx")
                .unwrap(),
            None
        );
    }
}

impl Repository<'_> {
    /// Persist one complete, validated set of output disclosures atomically.
    /// The service owns the versioned payload format and pool/output checks.
    pub fn put_payment_disclosures(
        &self,
        wallet_id: &str,
        network: &str,
        txid: &str,
        payload: &[u8],
    ) -> Result<()> {
        let envelope = DisclosureEnvelope {
            version: 1,
            wallet_id: wallet_id.to_owned(),
            network: network.to_owned(),
            txid: txid.to_owned(),
            payload: payload.to_vec(),
        };
        let plaintext = Zeroizing::new(
            serde_json::to_vec(&envelope)
                .map_err(|_| Error::Storage("Cannot encode payment disclosures".into()))?,
        );
        let encrypted = self.encrypt_blob(&plaintext)?;
        self.db.conn().execute(
            "INSERT INTO payment_disclosures (wallet_id, network, txid, payload)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(wallet_id, network, txid) DO UPDATE SET payload = excluded.payload",
            params![wallet_id, network, txid, encrypted],
        )?;
        Ok(())
    }

    /// Read and authenticate a bundle, returning no record on a cache miss.
    pub fn get_payment_disclosures(
        &self,
        wallet_id: &str,
        network: &str,
        txid: &str,
    ) -> Result<Option<Vec<u8>>> {
        let encrypted: Option<Vec<u8>> = self.db.conn().query_row(
            "SELECT payload FROM payment_disclosures WHERE wallet_id = ?1 AND network = ?2 AND txid = ?3",
            params![wallet_id, network, txid],
            |row| row.get(0),
        ).optional()?;
        let Some(encrypted) = encrypted else {
            return Ok(None);
        };
        let plaintext = Zeroizing::new(self.decrypt_blob(&encrypted)?);
        let envelope: DisclosureEnvelope = serde_json::from_slice(&plaintext)
            .map_err(|_| Error::Storage("Invalid payment disclosure record".into()))?;
        // Bind the encrypted contents to the lookup scope, so swapping valid
        // ciphertext between rows cannot disclose another wallet's record.
        if envelope.version != 1
            || envelope.wallet_id != wallet_id
            || envelope.network != network
            || envelope.txid != txid
        {
            return Err(Error::Validation(
                "Payment disclosure scope mismatch".into(),
            ));
        }
        Ok(Some(envelope.payload))
    }
}
