//! ZIP-32 interoperability and compatibility of historical Stashi Ironwood keys.

use bech32::{Bech32, Hrp};
use pirate_core::keys::{IronwoodExtendedFullViewingKey, IronwoodExtendedSpendingKey};
use pirate_params::NetworkType;

// Official Orchard ZIP-32 test vectors, also used by the node's Ironwood
// implementation: seed 0..31, paths m, m/1', m/1'/2', and m/1'/2'/3'.
// https://github.com/zcash/zcash-test-vectors/blob/master/zcash_test_vectors/orchard/zip32.py
const OFFICIAL_XSK: [&str; 4] = [
    "000000000000000000ab8b7a00509ef20e469b5292b61d474b7cffcb1657924cda720250ae405266777eee3c1017870990a3dd6891b82f80be8976c1e7dc20d60817a5e88e8b2cd4b8",
    "01ff4cda50010000806a041dfb9cfebee97cb1854fdc481cc04f02c9577aa6f13b2c445b80a9669a2298d703fcb40504c95b3b6ed10ecd50082cff97dfd1dd9aa0913c78f977c962af",
    "0232bbdc92020000806da8b57a36c77ad6412a9dc0115f12aced0ee01c402a0cf0a507cb17fc7bbd1d99afd8894baad58784d0ec08f5148ee2c2a17b2b294b08ef9e0a0cf14bcc0920",
    "0336a57c4f03000080b196e9b5809d76577a8944c3f8c8a83f93f0c8f5ace6e7bc9ce4396c034d93fe96439ea348a4b2ce4ec7beb4543c70274c8f76495d60c5fa5f018b68f3c32367",
];

fn seed() -> Vec<u8> {
    (0u8..32).collect()
}

#[test]
fn ironwood_extended_keys_match_official_zip32_vectors() {
    let mut key = IronwoodExtendedSpendingKey::master(&seed()).unwrap();

    for (depth, expected) in OFFICIAL_XSK.iter().enumerate() {
        if depth != 0 {
            key = key.derive_child(depth as u32).unwrap();
        }
        let expected = hex::decode(expected).unwrap();
        assert_eq!(
            key.to_bytes(),
            expected,
            "extended key at depth {depth} must match the full 73-byte ZIP-32 vector"
        );
        assert_eq!(
            IronwoodExtendedSpendingKey::from_bytes(&expected)
                .unwrap()
                .to_bytes(),
            expected
        );
    }
}

#[test]
fn ironwood_account_path_matches_node_known_answer() {
    // Independent m/32'/1'/0' values from the corrected node's tests.
    let account = IronwoodExtendedSpendingKey::master(&seed())
        .unwrap()
        .derive_account(1, 0)
        .unwrap();

    assert_eq!(
        account.inner.to_bytes().as_slice(),
        hex::decode("2b36c09b3ce22a7515cf180c37f6e690f7d51aadd9e66cc61136e1771eb66cce").unwrap()
    );
    assert_eq!(
        account.chain_code.as_slice(),
        hex::decode("f733058ddc0c94056200a17e329f13977f6d3716f2c630a2b6a47b049b09c529").unwrap()
    );
}

#[test]
fn historical_child_tag_import_preserves_key_addresses_and_descendants() {
    let correct_bytes = hex::decode(OFFICIAL_XSK[1]).unwrap();
    let standard = IronwoodExtendedSpendingKey::from_bytes(&correct_bytes).unwrap();

    // Older Stashi derived the same spending key and chain code, but wrote this
    // key's own FVK tag where its parent's tag belongs. The next official vector
    // contains that independently known tag in its parent_fvk_tag field.
    let next_bytes = hex::decode(OFFICIAL_XSK[2]).unwrap();
    let mut historical_bytes = correct_bytes.clone();
    historical_bytes[1..5].copy_from_slice(&next_bytes[1..5]);
    assert_ne!(historical_bytes, correct_bytes);

    let historical = IronwoodExtendedSpendingKey::from_bytes(&historical_bytes).unwrap();
    assert_eq!(historical.to_bytes(), historical_bytes);
    assert_eq!(historical.inner.to_bytes(), standard.inner.to_bytes());
    assert_eq!(historical.chain_code, standard.chain_code);

    let encoded = bech32::encode::<Bech32>(
        Hrp::parse("pirate-secret-extended-key").unwrap(),
        &historical_bytes,
    )
    .unwrap();
    let (imported, network) = IronwoodExtendedSpendingKey::from_bech32_any(&encoded).unwrap();
    assert_eq!(network, NetworkType::Mainnet);
    assert_eq!(imported.to_bytes(), historical_bytes);

    let historical_fvk_bytes = imported.to_extended_fvk().to_bytes();
    let historical_fvk = IronwoodExtendedFullViewingKey::from_bytes(&historical_fvk_bytes).unwrap();
    assert_eq!(historical_fvk.to_bytes(), historical_fvk_bytes);
    let standard_fvk = standard.to_extended_fvk();
    assert_eq!(historical_fvk.parent_fvk_tag, historical.parent_fvk_tag);
    assert_eq!(historical_fvk.to_ivk_bytes(), standard_fvk.to_ivk_bytes());
    assert_eq!(
        historical_fvk.to_internal_ivk_bytes(),
        standard_fvk.to_internal_ivk_bytes()
    );
    for index in [0, 1, 65_536] {
        assert_eq!(
            historical_fvk
                .address_at(index)
                .inner
                .to_raw_address_bytes(),
            standard_fvk.address_at(index).inner.to_raw_address_bytes()
        );
        assert_eq!(
            historical_fvk
                .address_at_internal(index)
                .inner
                .to_raw_address_bytes(),
            standard_fvk
                .address_at_internal(index)
                .inner
                .to_raw_address_bytes()
        );
    }

    let descendant = imported.derive_child(2).unwrap();
    assert_eq!(descendant.to_bytes(), next_bytes);
    assert_eq!(
        descendant.derive_child(3).unwrap().to_bytes(),
        hex::decode(OFFICIAL_XSK[3]).unwrap()
    );
}

#[test]
fn ironwood_key_identity_ignores_only_parent_tag() {
    let standard =
        IronwoodExtendedSpendingKey::from_bytes(&hex::decode(OFFICIAL_XSK[1]).unwrap()).unwrap();
    let mut historical = standard.clone();
    historical.parent_fvk_tag = hex::decode(OFFICIAL_XSK[2]).unwrap()[1..5]
        .try_into()
        .unwrap();
    assert_ne!(historical.parent_fvk_tag, standard.parent_fvk_tag);
    assert!(standard.same_key_material(&historical));
    assert!(historical.same_key_material(&standard));

    let standard_fvk = standard.to_extended_fvk();
    let historical_fvk = historical.to_extended_fvk();
    assert!(standard_fvk.same_key_material(&historical_fvk));
    assert!(historical_fvk.same_key_material(&standard_fvk));

    let mut different_chain = historical.clone();
    different_chain.chain_code[0] ^= 1;
    let mut different_depth = historical.clone();
    different_depth.depth += 1;
    let mut different_index = historical.clone();
    different_index.child_index += 1;
    let mut different_spending_key = historical.clone();
    different_spending_key.inner = standard.derive_child(2).unwrap().inner;

    for (difference, key) in [
        ("chain code", different_chain),
        ("depth", different_depth),
        ("child index", different_index),
        ("spending key", different_spending_key),
    ] {
        assert!(
            !standard.same_key_material(&key),
            "extended spending keys with different {difference} must remain distinct"
        );
        assert!(
            !standard_fvk.same_key_material(&key.to_extended_fvk()),
            "extended viewing keys with different {difference} must remain distinct"
        );
    }
}
