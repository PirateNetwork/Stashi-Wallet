//! Regression coverage for a bug where wallets created via
//! `import_viewing_wallet` (watch-only: no spending key, ever) could not
//! actually list balances or generate receive addresses.
//!
//! `ensure_primary_account_key` only recognized `KeyType::Seed` keys, so it
//! never found the `KeyType::ImportView` key `import_viewing_wallet` itself
//! creates, and fell through to a fallback that unconditionally tries to
//! decode `secret.extsk` as a Sapling spending key - always empty, and
//! therefore always an error, for a watch-only wallet. That broke
//! `list_address_balances` (and anything else that calls
//! `ensure_primary_account_key`). Current/next receive addresses must also
//! derive from viewing keys, including across the Ironwood activation.

use super::*;
use tempfile::tempdir;

#[test]
fn earlier_scan_birthday_survives_seed_and_viewing_wallet_reads() {
    let _guard = GLOBAL_WALLET_STATE_TEST_MUTEX.lock().unwrap();
    reset_global_wallet_state_for_tests();
    let temp_dir = tempdir().unwrap();
    configure_wallet_storage(
        temp_dir.path().to_string_lossy().to_string(),
        "test-passphrase-123".to_string(),
    )
    .unwrap();
    let source = create_wallet("source".into(), None, Some(3_000_000), None).unwrap();
    let watch = import_viewing_wallet(
        "watch".into(),
        Some(export_sapling_viewing_key(source.clone()).unwrap()),
        Some(export_ironwood_viewing_key(source.clone()).unwrap()),
        3_000_000,
    )
    .unwrap();
    for wallet_id in [source, watch] {
        let (_, repo) = open_wallet_db_for(&wallet_id).unwrap();
        let secret = repo.get_wallet_secret(&wallet_id).unwrap().unwrap();
        // The rescan uses an earlier height without changing registry metadata.
        let key_id = ensure_primary_account_key_at_birthday(&repo, &secret, 2_000_000).unwrap();
        assert_eq!(
            get_wallet_meta(&wallet_id).unwrap().birthday_height,
            3_000_000
        );
        list_key_groups(wallet_id.clone()).unwrap();
        list_address_balances(wallet_id.clone(), None).unwrap();
        generate_address_for_key(wallet_id.clone(), key_id, false).unwrap();
        assert_eq!(
            repo.get_account_key_by_id(key_id)
                .unwrap()
                .unwrap()
                .birthday_height,
            2_000_000
        );
        assert_eq!(repo.get_account_keys(secret.account_id).unwrap().len(), 1);
        assert_eq!(
            repo.get_wallet_secret(&wallet_id).unwrap().unwrap().extsk,
            secret.extsk
        );
    }
    reset_global_wallet_state_for_tests();
}

#[test]
fn watch_only_wallet_supports_balance_listing_and_address_generation() {
    let _guard = GLOBAL_WALLET_STATE_TEST_MUTEX.lock().unwrap();
    // Reset the process-wide wallet statics `configure_wallet_storage` mutates,
    // so this test neither inherits nor leaks an "unlocked" app.
    reset_global_wallet_state_for_tests();
    let temp_dir = tempdir().unwrap();

    configure_wallet_storage(
        temp_dir.path().to_string_lossy().to_string(),
        "test-passphrase-123".to_string(),
    )
    .unwrap();

    // A real seed-based wallet to export viewing keys from, exactly like an
    // operator would before handing them to a watch-only walletd instance.
    let source_wallet = create_wallet("source".to_string(), None, Some(1_000_000), None).unwrap();
    let sapling_vk = export_sapling_viewing_key(source_wallet.clone()).unwrap();
    let ironwood_vk = export_ironwood_viewing_key(source_wallet).unwrap();

    let watch_wallet = import_viewing_wallet(
        "btcpayserver".to_string(),
        Some(sapling_vk),
        Some(ironwood_vk),
        1_000_000,
    )
    .unwrap();

    let groups = list_key_groups(watch_wallet.clone()).unwrap();
    assert_eq!(
        groups.len(),
        1,
        "expected exactly one key group for a freshly imported watch-only wallet"
    );
    assert!(
        !groups[0].spendable,
        "an imported-viewing key group must never be marked spendable"
    );
    let key_id = groups[0].id;

    let account_error = add_next_seed_accounts(watch_wallet.clone(), 1)
        .expect_err("a viewing key must not derive sibling seed accounts");
    assert!(
        account_error
            .to_string()
            .contains("Seed accounts are unavailable for view-only wallets"),
        "unexpected account-derivation error: {account_error}"
    );

    // Regression: get_accounts (list_address_balances) used to fail here.
    // A fresh wallet seeds its index-0 addresses with zero balances rather
    // than returning an empty list, so check amounts, not list emptiness.
    let balances = list_address_balances(watch_wallet.clone(), None).unwrap();
    assert!(
        balances.iter().all(|b| b.balance == 0),
        "a fresh wallet with no synced notes should report zero balances, got {balances:?}"
    );

    // Regression: create_account/create_address used to fail here.
    let address = generate_address_for_key(watch_wallet.clone(), key_id, false).unwrap();
    assert!(
        address.starts_with("zs1"),
        "expected a mainnet Sapling address, got {address}"
    );

    let address2 = generate_address_for_key(watch_wallet.clone(), key_id, false).unwrap();
    assert_ne!(
        address, address2,
        "consecutive calls must mint distinct diversified addresses, like separate BTCPay invoices need"
    );

    let current = current_receive_address(watch_wallet.clone()).unwrap();
    assert!(current.starts_with("zs1"));
    let next = next_receive_address(watch_wallet.clone()).unwrap();
    assert_ne!(current, next);
    assert_eq!(current_receive_address(watch_wallet.clone()).unwrap(), next);
    {
        let (db, _) = open_wallet_db_for(&watch_wallet).unwrap();
        let storage = pirate_storage_sqlite::SyncStateStorage::new(&db);
        storage.save_sync_state(4_200_000, 4_200_000, 0).unwrap();
        storage
            .set_ironwood_activation_height(Some(4_200_000))
            .unwrap();
    }
    let ironwood = current_receive_address(watch_wallet.clone()).unwrap();
    assert!(ironwood.starts_with("pirate1"));
    assert_ne!(
        ironwood,
        next_receive_address(watch_wallet.clone()).unwrap()
    );
    assert!(list_addresses(watch_wallet)
        .unwrap()
        .iter()
        .any(|entry| entry.address == next));

    // Reset the process-wide wallet statics `configure_wallet_storage` mutates,
    // so this test neither inherits nor leaks an "unlocked" app.
    reset_global_wallet_state_for_tests();
}
