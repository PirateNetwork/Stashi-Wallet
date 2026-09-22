//! Wallet-service-level regression coverage for the durable sync-interruption
//! latch and for the rule that only a server-verified height may be recorded as
//! the wallet's known chain tip.
//!
//! Both bugs were invisible to the existing storage-level tests.
//!
//! * `mark_sync_interrupted` wrote `spendable = 0` and `ERR_SYNC_FINALIZING`
//!   and the storage test asserted exactly that. The public status never reads
//!   either column: it recomputes spendability from the rescan/repair gates and
//!   the anchor heights, so a wallet validated by an earlier run reported
//!   `spendable: true` / `OK` on the very next poll after a sync failed, with a
//!   stale anchor. These tests therefore exercise `get_spendability_status`,
//!   the function callers actually see, rather than the storage row.
//! * `start_sync` recorded its local resume height (or, on a fresh wallet, the
//!   user-supplied birthday) as the known tip before it had read the endpoint
//!   configuration, let alone contacted a server. `validate_import_birthday`
//!   then trusted that value.

use super::*;
use pirate_storage_sqlite::SpendabilityStateStorage;
use tempfile::tempdir;

fn test_runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("test runtime should build")
}

/// Put a wallet into the state a completed, validated sync leaves behind:
/// spendable at a validated anchor, with no rescan, replay or repair
/// obligation outstanding.
fn mark_previously_validated(wallet_id: &str, anchor_height: u64) {
    let (db, _repo) = open_wallet_db_for(wallet_id).unwrap();
    SpendabilityStateStorage::new(&db)
        .mark_validated(anchor_height.saturating_add(1), anchor_height)
        .unwrap();
}

fn mark_interrupted(wallet_id: &str) {
    let (db, _repo) = open_wallet_db_for(wallet_id).unwrap();
    SpendabilityStateStorage::new(&db)
        .mark_sync_interrupted()
        .unwrap();
}

fn record_verified_tip(wallet_id: &str, tip_height: u64) {
    let (db, _repo) = open_wallet_db_for(wallet_id).unwrap();
    SpendabilityStateStorage::new(&db)
        .record_known_sync_height(tip_height)
        .unwrap();
}

#[test]
fn opening_a_legacy_wallet_gates_notes_hidden_by_a_later_birthday() {
    let _guard = GLOBAL_WALLET_STATE_TEST_MUTEX.lock().unwrap();
    reset_global_wallet_state_for_tests();
    let temp_dir = tempdir().unwrap();
    configure_wallet_storage(
        temp_dir.path().to_string_lossy().to_string(),
        "test-passphrase-123".into(),
    )
    .unwrap();
    let wallet_id = create_wallet("Birthday recovery".into(), None, Some(3_000_000), None).unwrap();
    mark_previously_validated(&wallet_id, 4_100_000);
    {
        let (db, repo) = open_wallet_db_for(&wallet_id).unwrap();
        let secret = repo.get_wallet_secret(&wallet_id).unwrap().unwrap();
        let key_id = repo.get_account_keys(secret.account_id).unwrap()[0].id;
        repo.insert_note(&pirate_storage_sqlite::models::NoteRecord {
            id: None,
            account_id: secret.account_id,
            key_id,
            note_type: pirate_storage_sqlite::models::NoteType::Sapling,
            value: 100_000,
            nullifier: vec![0x41; 32],
            commitment: vec![0x42; 32],
            spent: false,
            height: 2_000_000,
            txid: vec![0x43; 32],
            output_index: 0,
            address_id: None,
            spent_txid: None,
            diversifier: None,
            note: None,
            position: None,
            memo: None,
        })
        .unwrap();
        // Reproduce an old installation that has not applied this recovery.
        db.conn()
            .execute(
                "DELETE FROM migration_state WHERE key = ?1",
                [format!("note_birthday_recovery_v1:{}", secret.account_id)],
            )
            .unwrap();
    }
    encrypted_db::invalidate_wallet_db_cache_for(&wallet_id);
    let status = get_spendability_status(wallet_id.clone()).unwrap();
    assert!(!status.spendable);
    assert!(status.repair_queued);
    assert!(!status.rescan_required);
    assert_eq!(
        status.reason_code,
        SPENDABILITY_REASON_ERR_WITNESS_REPAIR_QUEUED
    );
    assert_eq!(status.validated_anchor_height, 4_100_000);
    // Recovery survives reopening; it does not depend on UI cache refreshes.
    encrypted_db::invalidate_wallet_db_cache_for(&wallet_id);
    assert!(
        get_spendability_status(wallet_id.clone())
            .unwrap()
            .repair_queued
    );
    reset_global_wallet_state_for_tests();
}

#[test]
fn ordinary_import_durably_requires_replay_before_background_sync() {
    let _guard = GLOBAL_WALLET_STATE_TEST_MUTEX.lock().unwrap();
    reset_global_wallet_state_for_tests();
    let temp_dir = tempdir().unwrap();
    configure_wallet_storage(
        temp_dir.path().to_string_lossy().to_string(),
        "test-passphrase-123".into(),
    )
    .unwrap();
    let wallet_id = create_wallet("Import recovery".into(), None, Some(3_000_000), None).unwrap();
    record_verified_tip(&wallet_id, 3_100_000);
    let key = ExtendedSpendingKey::from_mnemonic(
        "legal winner thank year wave sausage worth useful legal winner thank yellow",
    )
    .unwrap();
    let encoded = zcash_client_backend::encoding::encode_extended_spending_key(
        "secret-extended-key-main",
        key.inner(),
    );
    assert!(import_spending_key(
        wallet_id.clone(),
        Some(encoded.clone()),
        None,
        None,
        3_200_000
    )
    .unwrap_err()
    .to_string()
    .contains("exceeds"));
    let id = import_spending_key(wallet_id.clone(), Some(encoded), None, None, 200_000).unwrap();
    // Reopen storage without making the UI's second rescan call: this is the
    // crash/navigation boundary that previously left a key with no replay gate.
    let (db, repo) = open_wallet_db_for(&wallet_id).unwrap();
    let stored = repo
        .get_account_keys(
            repo.get_wallet_secret(&wallet_id)
                .unwrap()
                .unwrap()
                .account_id,
        )
        .unwrap();
    assert_eq!(
        stored
            .iter()
            .find(|k| k.id == Some(id))
            .unwrap()
            .sapling_extsk,
        Some(key.to_bytes())
    );
    let state = SpendabilityStateStorage::new(&db).load_state().unwrap();
    assert!(state.rescan_required);
    assert!(!state.spendable);
    assert_eq!(state.required_rescan_from_height, 200_000);
    drop(repo);
    drop(db);
    let error = test_runtime()
        .block_on(sync_control::acquire_background_sync(&wallet_id))
        .unwrap_err();
    assert!(error.to_string().contains("imported-key history"));
    reset_global_wallet_state_for_tests();
}

#[test]
fn an_interrupted_sync_makes_the_public_status_report_not_spendable() {
    let _guard = GLOBAL_WALLET_STATE_TEST_MUTEX.lock().unwrap();
    reset_global_wallet_state_for_tests();
    let temp_dir = tempdir().unwrap();
    configure_wallet_storage(
        temp_dir.path().to_string_lossy().to_string(),
        "test-passphrase-123".to_string(),
    )
    .unwrap();

    let wallet_id = create_wallet("validated".to_string(), None, Some(152_855), None).unwrap();
    mark_previously_validated(&wallet_id, 152_850);

    // Baseline: a validated wallet with no rescan or repair obligation is
    // spendable. Without this the regression assertion below would pass
    // vacuously.
    let before = get_spendability_status(wallet_id.clone()).unwrap();
    assert!(
        before.spendable,
        "expected a validated wallet to be spendable"
    );
    assert!(!before.rescan_required);
    assert!(!before.repair_queued);
    assert_eq!(before.reason_code, "OK");

    // The transition `start_sync` performs when the sync task returns an error.
    mark_interrupted(&wallet_id);

    let after = get_spendability_status(wallet_id.clone()).unwrap();
    assert!(
        !after.spendable,
        "a failed sync must not leave the stale anchor reported as spendable"
    );
    assert_eq!(after.reason_code, "ERR_SYNC_FINALIZING");
    // The interruption gates spending without destroying the heights the
    // failed run had already verified.
    assert_eq!(after.anchor_height, before.anchor_height);
    assert_eq!(
        after.validated_anchor_height,
        before.validated_anchor_height
    );
    assert_eq!(after.target_height, before.target_height);

    reset_global_wallet_state_for_tests();
}

#[test]
fn a_rescan_obligation_keeps_precedence_over_the_interruption_latch() {
    let _guard = GLOBAL_WALLET_STATE_TEST_MUTEX.lock().unwrap();
    reset_global_wallet_state_for_tests();
    let temp_dir = tempdir().unwrap();
    configure_wallet_storage(
        temp_dir.path().to_string_lossy().to_string(),
        "test-passphrase-123".to_string(),
    )
    .unwrap();

    let wallet_id = create_wallet("gated".to_string(), None, Some(152_855), None).unwrap();
    mark_previously_validated(&wallet_id, 152_850);
    {
        let (db, _repo) = open_wallet_db_for(&wallet_id).unwrap();
        SpendabilityStateStorage::new(&db)
            .mark_rescan_required("ERR_RESCAN_REQUIRED")
            .unwrap();
    }
    mark_interrupted(&wallet_id);

    // The latch must not weaken the more specific rescan reason code.
    let status = get_spendability_status(wallet_id.clone()).unwrap();
    assert!(!status.spendable);
    assert!(status.rescan_required);
    assert_eq!(status.reason_code, "ERR_RESCAN_REQUIRED");

    reset_global_wallet_state_for_tests();
}

#[test]
fn validating_an_anchor_again_clears_the_interruption_latch() {
    let _guard = GLOBAL_WALLET_STATE_TEST_MUTEX.lock().unwrap();
    reset_global_wallet_state_for_tests();
    let temp_dir = tempdir().unwrap();
    configure_wallet_storage(
        temp_dir.path().to_string_lossy().to_string(),
        "test-passphrase-123".to_string(),
    )
    .unwrap();

    let wallet_id = create_wallet("recovering".to_string(), None, Some(152_855), None).unwrap();
    mark_previously_validated(&wallet_id, 152_850);
    mark_interrupted(&wallet_id);
    assert!(
        !get_spendability_status(wallet_id.clone())
            .unwrap()
            .spendable
    );

    // A later run that validates an anchor releases the latch, so the gate
    // cannot become permanent.
    mark_previously_validated(&wallet_id, 152_860);

    let status = get_spendability_status(wallet_id.clone()).unwrap();
    assert!(status.spendable);
    assert_eq!(status.reason_code, "OK");
    assert_eq!(status.validated_anchor_height, 152_860);

    reset_global_wallet_state_for_tests();
}

/// The lock is held across `block_on` rather than across an `.await` so no
/// guard is held over a yield point, matching `background::tests`.
#[test]
fn starting_a_sync_does_not_record_an_unverified_local_start_height() {
    let _guard = GLOBAL_WALLET_STATE_TEST_MUTEX.lock().unwrap();
    reset_global_wallet_state_for_tests();
    let runtime = test_runtime();
    let temp_dir = tempdir().unwrap();
    configure_wallet_storage(
        temp_dir.path().to_string_lossy().to_string(),
        "test-passphrase-123".to_string(),
    )
    .unwrap();

    let birthday_height = 152_900_u32;
    let wallet_id = create_wallet("fresh".to_string(), None, Some(birthday_height), None).unwrap();
    assert_eq!(
        get_spendability_status(wallet_id.clone())
            .unwrap()
            .target_height,
        0
    );

    // Direct transport to a closed local port. The test never leaves the
    // machine and the engine can never obtain a validated server snapshot, so
    // no height may be recorded.
    tunnel::set_tunnel(TunnelMode::Direct).unwrap();
    set_lightd_endpoint(wallet_id.clone(), "http://127.0.0.1:1".to_string(), None).unwrap();

    // `start_sync` returns once the sync task has been spawned. The removed
    // call recorded `start_height` synchronously before that point, so this
    // assertion is deterministic and does not depend on how the spawned task
    // fares.
    let _ = runtime.block_on(start_sync(wallet_id.clone(), SyncMode::Compact));

    let status = get_spendability_status(wallet_id.clone()).unwrap();
    assert_eq!(
        status.target_height, 0,
        "the wallet birthday is not a verified chain tip and must not be recorded as one"
    );
    assert!(!status.spendable);

    // The tip gate that depends on it therefore still refuses the import that
    // motivated this PR.
    let import_error = runtime
        .block_on(import_spending_key_verified(
            wallet_id.clone(),
            VerifiedSpendingKeyPool::Sapling,
            "not-a-key".to_string(),
            "not-an-address".to_string(),
            0,
            None,
            birthday_height,
        ))
        .expect_err("an import must be refused while the chain tip is unknown");
    assert!(
        import_error.to_string().contains("chain tip is unknown"),
        "unexpected import error: {import_error}"
    );

    let _ = runtime.block_on(cancel_sync(wallet_id.clone()));
    sync_control::clear_wallet_sync_state(&wallet_id);
    reset_global_wallet_state_for_tests();
}

#[test]
fn a_verified_tip_is_recorded_and_bounds_the_import_birthday() {
    let _guard = GLOBAL_WALLET_STATE_TEST_MUTEX.lock().unwrap();
    reset_global_wallet_state_for_tests();
    let runtime = test_runtime();
    let temp_dir = tempdir().unwrap();
    configure_wallet_storage(
        temp_dir.path().to_string_lossy().to_string(),
        "test-passphrase-123".to_string(),
    )
    .unwrap();

    let wallet_id = create_wallet("synced".to_string(), None, Some(152_855), None).unwrap();

    // What `SyncEngine` now does once `validated_server_info()` has verified
    // the remote snapshot: it records `info.block_height`, and nothing else.
    let verified_tip = 152_950_u64;
    record_verified_tip(&wallet_id, verified_tip);
    assert_eq!(
        get_spendability_status(wallet_id.clone())
            .unwrap()
            .target_height,
        verified_tip
    );

    let above_tip = runtime
        .block_on(import_spending_key_verified(
            wallet_id.clone(),
            VerifiedSpendingKeyPool::Sapling,
            "not-a-key".to_string(),
            "not-an-address".to_string(),
            0,
            None,
            u32::try_from(verified_tip).unwrap() + 1,
        ))
        .expect_err("a birthday above the verified tip must be refused");
    assert!(
        above_tip
            .to_string()
            .contains("exceeds the wallet's known chain tip"),
        "unexpected import error: {above_tip}"
    );

    // A birthday within the verified tip clears the tip gate and fails later,
    // on key verification, which is what proves the gate was passed.
    let within_tip = runtime
        .block_on(import_spending_key_verified(
            wallet_id.clone(),
            VerifiedSpendingKeyPool::Sapling,
            "not-a-key".to_string(),
            "not-an-address".to_string(),
            0,
            None,
            u32::try_from(verified_tip).unwrap(),
        ))
        .expect_err("a bogus spending key must still be rejected");
    let message = within_tip.to_string();
    assert!(
        !message.contains("chain tip"),
        "birthday gate should have passed, got: {message}"
    );

    reset_global_wallet_state_for_tests();
}
