//! Offline reproduction: imported-key history must survive a restart.
use pirate_core::keys::ExtendedSpendingKey;
use pirate_params::NetworkType;
use pirate_storage_sqlite::{
    Account, AccountKey, Database, EncryptionAlgorithm, EncryptionKey, KeyScope, KeyType,
    MasterKey, Repository, SyncStateStorage, WalletSecret,
};
use pirate_sync_lightd::SyncEngine;

#[test]
fn imported_key_resume_must_not_skip_older_history() {
    assert_resume_height(250_000, 250_001);
}

#[test]
fn imported_key_starts_at_its_birthday_without_a_scan_cursor() {
    assert_resume_height(0, 200_000);
}

fn assert_resume_height(cursor: u64, expected: u64) {
    let file = tempfile::NamedTempFile::new().unwrap();
    let encryption = EncryptionKey::from_passphrase("audit-only", &[0x51; 32]).unwrap();
    let master = MasterKey::generate(EncryptionAlgorithm::ChaCha20Poly1305);
    let db = Database::open(file.path(), &encryption, master.clone()).unwrap();
    let repo = Repository::new(&db);
    let account_id = repo
        .insert_account(&Account {
            id: None,
            name: "Audit fixture".into(),
            created_at: 1,
        })
        .unwrap();
    let primary = ExtendedSpendingKey::from_mnemonic(
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    ).unwrap();
    let imported = ExtendedSpendingKey::from_mnemonic(
        "legal winner thank year wave sausage worth useful legal winner thank yellow",
    )
    .unwrap();
    let secret = WalletSecret {
        wallet_id: "audit-wallet".into(),
        account_id,
        extsk: primary.to_bytes(),
        dfvk: Some(primary.to_extended_fvk().to_bytes()),
        orchard_extsk: None,
        sapling_ivk: None,
        orchard_ivk: None,
        encrypted_mnemonic: None,
        mnemonic_language: None,
        created_at: 1,
    };
    repo.upsert_wallet_secret(&repo.encrypt_wallet_secret_fields(&secret).unwrap())
        .unwrap();
    for (key_type, key, birthday) in [
        (KeyType::Seed, primary, 3_000_000),
        (KeyType::ImportSpend, imported, 200_000),
    ] {
        let key = AccountKey {
            id: None,
            account_id,
            key_type,
            key_scope: KeyScope::Account,
            label: None,
            birthday_height: birthday,
            created_at: 1,
            spendable: true,
            sapling_extsk: Some(key.to_bytes()),
            sapling_dfvk: Some(key.to_extended_fvk().to_bytes()),
            orchard_extsk: None,
            orchard_fvk: None,
            encrypted_mnemonic: None,
        };
        repo.upsert_account_key(&repo.encrypt_account_key_fields(&key).unwrap())
            .unwrap();
    }
    // Reopen the engine either before scanning or partway through recovery.
    SyncStateStorage::new(&db).reset_sync_state(cursor).unwrap();
    assert_eq!(
        repo.get_wallet_birthday_height(account_id).unwrap(),
        Some(200_000)
    );
    drop(repo);
    drop(db);
    // Normal service startup passes wallet metadata's original birthday.
    let engine = SyncEngine::new("http://127.0.0.1:8067".into(), 3_000_000)
        .with_wallet_at_path(
            secret.wallet_id,
            file.path().to_path_buf(),
            EncryptionKey::from_bytes(*encryption.as_bytes()),
            master,
            NetworkType::Mainnet,
            NetworkType::Mainnet,
        )
        .unwrap();
    assert_eq!(engine.background_resume_height().unwrap(), expected);
}
