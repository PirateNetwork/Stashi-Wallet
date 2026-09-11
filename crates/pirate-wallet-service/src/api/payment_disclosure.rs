use super::*;
use bech32::{Bech32, Hrp};
use sapling::note_encryption::{prf_ock, try_sapling_output_recovery_with_ock};
use std::convert::TryInto;
use zcash_note_encryption::{try_output_recovery_with_ock, Domain, EphemeralKeyBytes};
use zcash_primitives::transaction::components::sapling::zip212_enforcement;
use zcash_primitives::transaction::{Transaction, TxId as ZcashTxId};

const SAPLING_DISCLOSURE_MAINNET_HRP: &str = "pirate-sapling-payment-disclosure";
const IRONWOOD_DISCLOSURE_MAINNET_HRP: &str = "pirate-ironwood-payment-disclosure";
const SAPLING_DISCLOSURE_TESTNET_HRP: &str = "zdisctest";
const IRONWOOD_DISCLOSURE_TESTNET_HRP: &str = "idisctest";
const SAPLING_DISCLOSURE_REGTEST_HRP: &str = "zdiscregtest";
const IRONWOOD_DISCLOSURE_REGTEST_HRP: &str = "idiscregtest";
const DISCLOSURE_PAYLOAD_LEN: usize = 32 + 4 + 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DisclosureKind {
    Sapling,
    Ironwood,
}

impl DisclosureKind {
    fn as_str(self) -> &'static str {
        match self {
            DisclosureKind::Sapling => "sapling",
            DisclosureKind::Ironwood => "ironwood",
        }
    }
}

#[derive(Debug, Clone)]
struct DecodedDisclosure {
    kind: DisclosureKind,
    network_type: NetworkType,
    txid_bytes: [u8; 32],
    output_index: u32,
    ock: [u8; 32],
}

#[derive(Debug, Clone)]
struct RawTransactionFetch {
    bytes: Vec<u8>,
    height: Option<u32>,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct StoredDisclosures {
    version: u32,
    recovery_keys: [u8; 32],
    outputs: Vec<PaymentDisclosure>,
}

fn recovery_key_fingerprint(
    sapling: &[SaplingOutgoingViewingKey],
    ironwood: &[orchard::keys::OutgoingViewingKey],
) -> [u8; 32] {
    let mut keys: Vec<[u8; 32]> = ovk_candidate_bytes(sapling, ironwood, DisclosureKind::Sapling);
    keys.sort_unstable();
    let mut hash = Sha256::new();
    hash.update(b"payment-disclosure-recovery-keys-v1");
    for key in keys {
        hash.update(key);
    }
    hash.finalize().into()
}

fn sapling_disclosure_hrp(network_type: NetworkType) -> &'static str {
    match network_type {
        NetworkType::Mainnet => SAPLING_DISCLOSURE_MAINNET_HRP,
        NetworkType::Testnet => SAPLING_DISCLOSURE_TESTNET_HRP,
        NetworkType::Regtest => SAPLING_DISCLOSURE_REGTEST_HRP,
    }
}

fn ironwood_disclosure_hrp(network_type: NetworkType) -> &'static str {
    match network_type {
        NetworkType::Mainnet => IRONWOOD_DISCLOSURE_MAINNET_HRP,
        NetworkType::Testnet => IRONWOOD_DISCLOSURE_TESTNET_HRP,
        NetworkType::Regtest => IRONWOOD_DISCLOSURE_REGTEST_HRP,
    }
}

fn disclosure_hrp(kind: DisclosureKind, network_type: NetworkType) -> &'static str {
    match kind {
        DisclosureKind::Sapling => sapling_disclosure_hrp(network_type),
        DisclosureKind::Ironwood => ironwood_disclosure_hrp(network_type),
    }
}

fn disclosure_kind_for_hrp(hrp: &str) -> Option<(DisclosureKind, NetworkType)> {
    match hrp {
        SAPLING_DISCLOSURE_MAINNET_HRP => Some((DisclosureKind::Sapling, NetworkType::Mainnet)),
        IRONWOOD_DISCLOSURE_MAINNET_HRP => Some((DisclosureKind::Ironwood, NetworkType::Mainnet)),
        SAPLING_DISCLOSURE_TESTNET_HRP => Some((DisclosureKind::Sapling, NetworkType::Testnet)),
        IRONWOOD_DISCLOSURE_TESTNET_HRP => Some((DisclosureKind::Ironwood, NetworkType::Testnet)),
        SAPLING_DISCLOSURE_REGTEST_HRP => Some((DisclosureKind::Sapling, NetworkType::Regtest)),
        IRONWOOD_DISCLOSURE_REGTEST_HRP => Some((DisclosureKind::Ironwood, NetworkType::Regtest)),
        _ => None,
    }
}

fn encode_payment_disclosure(
    kind: DisclosureKind,
    network_type: NetworkType,
    txid_bytes: &[u8; 32],
    output_index: u32,
    ock: &[u8; 32],
) -> Result<String> {
    let mut payload = Vec::with_capacity(DISCLOSURE_PAYLOAD_LEN);
    payload.extend_from_slice(txid_bytes);
    payload.extend_from_slice(&output_index.to_le_bytes());
    payload.extend_from_slice(ock);

    let hrp = Hrp::parse(disclosure_hrp(kind, network_type))
        .map_err(|e| anyhow!("Invalid payment disclosure HRP: {}", e))?;
    bech32::encode::<Bech32>(hrp, &payload)
        .map_err(|e| anyhow!("Failed to encode payment disclosure: {}", e))
}

fn decode_payment_disclosure(disclosure: &str) -> Result<DecodedDisclosure> {
    let normalized = disclosure
        .trim()
        .strip_prefix("zpd:")
        .unwrap_or_else(|| disclosure.trim());
    let (hrp, payload) = bech32::decode(normalized)
        .map_err(|e| anyhow!("Invalid payment disclosure encoding: {}", e))?;
    let (kind, network_type) = disclosure_kind_for_hrp(&hrp.to_string())
        .ok_or_else(|| anyhow!("Unsupported payment disclosure prefix: {}", hrp))?;

    if payload.len() != DISCLOSURE_PAYLOAD_LEN {
        return Err(anyhow!(
            "Invalid payment disclosure payload length: {} (expected {})",
            payload.len(),
            DISCLOSURE_PAYLOAD_LEN
        ));
    }

    let txid_bytes: [u8; 32] = payload[0..32]
        .try_into()
        .map_err(|_| anyhow!("Invalid transaction id bytes in disclosure"))?;
    let output_index = u32::from_le_bytes(
        payload[32..36]
            .try_into()
            .map_err(|_| anyhow!("Invalid output index bytes in disclosure"))?,
    );
    let ock: [u8; 32] = payload[36..68]
        .try_into()
        .map_err(|_| anyhow!("Invalid OCK bytes in disclosure"))?;

    Ok(DecodedDisclosure {
        kind,
        network_type,
        txid_bytes,
        output_index,
        ock,
    })
}

fn memo_to_text(memo: &[u8]) -> Option<String> {
    if memo.iter().all(|b| *b == 0) {
        None
    } else {
        pirate_sync_lightd::sapling::full_decrypt::decode_memo(memo)
    }
}

fn txid_string(txid_bytes: &[u8; 32]) -> String {
    ZcashTxId::from_bytes(*txid_bytes).to_string()
}

fn push_unique_ovk(bytes: [u8; 32], seen: &mut HashSet<[u8; 32]>, out: &mut Vec<[u8; 32]>) {
    if seen.insert(bytes) {
        out.push(bytes);
    }
}

fn ovk_candidate_bytes(
    sapling_ovks: &[SaplingOutgoingViewingKey],
    orchard_ovks: &[orchard::keys::OutgoingViewingKey],
    primary: DisclosureKind,
) -> Vec<[u8; 32]> {
    let mut seen = HashSet::new();
    let mut candidates = Vec::new();

    let push_sapling = |seen: &mut HashSet<[u8; 32]>, candidates: &mut Vec<[u8; 32]>| {
        for ovk in sapling_ovks {
            push_unique_ovk(ovk.0, seen, candidates);
        }
    };
    let push_orchard = |seen: &mut HashSet<[u8; 32]>, candidates: &mut Vec<[u8; 32]>| {
        for ovk in orchard_ovks {
            push_unique_ovk(*ovk.as_ref(), seen, candidates);
        }
    };

    match primary {
        DisclosureKind::Sapling => {
            push_sapling(&mut seen, &mut candidates);
            push_orchard(&mut seen, &mut candidates);
        }
        DisclosureKind::Ironwood => {
            push_orchard(&mut seen, &mut candidates);
            push_sapling(&mut seen, &mut candidates);
        }
    }

    candidates
}

fn recover_payment_disclosures_from_raw_tx(
    raw_tx_bytes: &[u8],
    tx_height: Option<u32>,
    sapling_ovks: &[SaplingOutgoingViewingKey],
    orchard_ovks: &[orchard::keys::OutgoingViewingKey],
    network_type: NetworkType,
) -> Vec<PaymentDisclosure> {
    let tx = match read_pirate_transaction(raw_tx_bytes) {
        Ok(tx) => tx,
        Err(_) => return Vec::new(),
    };
    let txid_bytes = *tx.txid().as_ref();
    recover_payment_disclosures_from_tx(
        &tx,
        &txid_bytes,
        tx_height,
        sapling_ovks,
        orchard_ovks,
        network_type,
    )
}

fn recover_payment_disclosures_from_tx(
    tx: &Transaction,
    txid_bytes: &[u8; 32],
    tx_height: Option<u32>,
    sapling_ovks: &[SaplingOutgoingViewingKey],
    orchard_ovks: &[orchard::keys::OutgoingViewingKey],
    network_type: NetworkType,
) -> Vec<PaymentDisclosure> {
    let mut disclosures = Vec::new();
    if sapling_ovks.is_empty() && orchard_ovks.is_empty() {
        return disclosures;
    }

    let network = PirateNetwork::new(network_type);
    let block_height = BlockHeight::from_u32(tx_height.unwrap_or(0));
    let sapling_zip212 = zip212_enforcement(&network, block_height);
    let txid = txid_string(txid_bytes);

    if let Some(bundle) = tx.sapling_bundle() {
        let candidates = ovk_candidate_bytes(sapling_ovks, orchard_ovks, DisclosureKind::Sapling);
        for (idx, output) in bundle.shielded_outputs().iter().enumerate() {
            for ovk_bytes in &candidates {
                let ovk = SaplingOutgoingViewingKey(*ovk_bytes);
                let cmu_bytes = output.cmu().to_bytes();
                let ock = prf_ock(&ovk, output.cv(), &cmu_bytes, output.ephemeral_key());
                if let Some((note, address, memo)) =
                    try_sapling_output_recovery_with_ock(&ock, output, sapling_zip212)
                {
                    let ock_bytes = ock.0;
                    let disclosure = match encode_payment_disclosure(
                        DisclosureKind::Sapling,
                        network_type,
                        txid_bytes,
                        idx as u32,
                        &ock_bytes,
                    ) {
                        Ok(value) => value,
                        Err(_) => break,
                    };
                    let memo_vec = memo.to_vec();
                    disclosures.push(PaymentDisclosure {
                        disclosure_type: DisclosureKind::Sapling.as_str().to_string(),
                        txid: txid.clone(),
                        output_index: idx as u32,
                        address: PaymentAddress { inner: address }.encode_for_network(network_type),
                        amount: note.value().inner(),
                        memo: memo_to_text(&memo_vec),
                        disclosure,
                    });
                    break;
                }
            }
        }
    }

    if let Some(bundle) = tx.ironwood_bundle() {
        let candidates = ovk_candidate_bytes(sapling_ovks, orchard_ovks, DisclosureKind::Ironwood);
        for (idx, action) in bundle.actions().iter().enumerate() {
            for ovk_bytes in &candidates {
                let ovk = orchard::keys::OutgoingViewingKey::from(*ovk_bytes);
                let epk = EphemeralKeyBytes(action.encrypted_note().epk_bytes);
                let cmx_bytes = action.cmx().to_bytes();
                let ock =
                    <IronwoodDomain as Domain>::derive_ock(&ovk, action.cv_net(), &cmx_bytes, &epk);
                let domain = IronwoodDomain::for_action(action);
                if let Some((note, address, memo)) = try_output_recovery_with_ock(
                    &domain,
                    &ock,
                    action,
                    &action.encrypted_note().out_ciphertext,
                ) {
                    let ock_bytes = ock.0;
                    let disclosure = match encode_payment_disclosure(
                        DisclosureKind::Ironwood,
                        network_type,
                        txid_bytes,
                        idx as u32,
                        &ock_bytes,
                    ) {
                        Ok(value) => value,
                        Err(_) => break,
                    };
                    let memo_vec = memo.to_vec();
                    let address_string = match (IronwoodPaymentAddress { inner: address })
                        .encode_for_network(network_type)
                    {
                        Ok(address) => address,
                        Err(_) => continue,
                    };
                    disclosures.push(PaymentDisclosure {
                        disclosure_type: DisclosureKind::Ironwood.as_str().to_string(),
                        txid: txid.clone(),
                        output_index: idx as u32,
                        address: address_string,
                        amount: note.value().inner(),
                        memo: memo_to_text(&memo_vec),
                        disclosure,
                    });
                    break;
                }
            }
        }
    }

    disclosures
}

pub(super) fn recover_outgoing_recipients_with_disclosures_from_raw_tx(
    raw_tx_bytes: &[u8],
    tx_height: Option<u32>,
    sapling_ovks: &[SaplingOutgoingViewingKey],
    orchard_ovks: &[orchard::keys::OutgoingViewingKey],
    network_type: NetworkType,
) -> Vec<TransactionRecipient> {
    recover_payment_disclosures_from_raw_tx(
        raw_tx_bytes,
        tx_height,
        sapling_ovks,
        orchard_ovks,
        network_type,
    )
    .into_iter()
    .map(|disclosure| TransactionRecipient {
        address: disclosure.address,
        pool: disclosure.disclosure_type,
        amount: disclosure.amount,
        output_index: disclosure.output_index,
        memo: disclosure.memo,
        payment_disclosure: Some(disclosure.disclosure),
    })
    .collect()
}

async fn fetch_raw_transaction(
    endpoint_config: endpoint::LightdEndpoint,
    tx_hash_candidates: Vec<[u8; 32]>,
) -> Result<RawTransactionFetch> {
    let client_config = tunnel::light_client_config_for_endpoint(
        &endpoint_config,
        RetryConfig::default(),
        Duration::from_secs(30),
        Duration::from_secs(60),
    );
    let client = LightClient::with_config(client_config);
    client
        .connect()
        .await
        .map_err(|e| anyhow!("Failed to connect to lightwalletd: {}", e))?;

    let mut last_fetch_err: Option<String> = None;
    for tx_hash in tx_hash_candidates {
        match client.get_raw_transaction(&tx_hash).await {
            Ok(raw) => {
                let height = raw.height.and_then(|height| u32::try_from(height).ok());
                return Ok(RawTransactionFetch {
                    bytes: raw.data,
                    height,
                });
            }
            Err(e) => last_fetch_err = Some(e.to_string()),
        }
    }

    Err(anyhow!(
        "Failed to fetch raw transaction: {}",
        last_fetch_err.unwrap_or_else(|| "unknown error".to_string())
    ))
}

/// Export all payment disclosures recoverable by this wallet for an outgoing transaction.
pub async fn export_payment_disclosures(
    wallet_id: WalletId,
    txid: String,
) -> Result<Vec<PaymentDisclosure>> {
    run_on_runtime(move || export_payment_disclosures_inner(wallet_id, txid)).await
}

async fn export_payment_disclosures_inner(
    wallet_id: WalletId,
    txid: String,
) -> Result<Vec<PaymentDisclosure>> {
    export_payment_disclosures_with_fetch(wallet_id, txid, fetch_raw_transaction).await
}

async fn export_payment_disclosures_with_fetch<F, Fut>(
    wallet_id: WalletId,
    txid: String,
    fetch: F,
) -> Result<Vec<PaymentDisclosure>>
where
    F: FnOnce(endpoint::LightdEndpoint, Vec<[u8; 32]>) -> Fut,
    Fut: Future<Output = Result<RawTransactionFetch>>,
{
    let txid = normalize_disclosure_txid(&txid)?;
    let chain_network = wallet_network_type(&wallet_id)?;
    let network_type = address_prefix_network_type(&wallet_id)?;
    // Some test endpoints intentionally use mainnet address prefixes. Cache
    // isolation must follow the actual chain, not that encoding compatibility.
    let network = disclosure_network_name(chain_network);
    // Local key metadata only; this does not open a network connection.
    let (endpoint_config, tx_hash_candidates, sapling_ovks, orchard_ovks, tx_height_hint) =
        collect_tx_recovery_context(&wallet_id, &txid)?;
    let recovery_keys = recovery_key_fingerprint(&sapling_ovks, &orchard_ovks);
    // Opening the wallet enforces the current unlocked session even on hits.
    // Drop repository handles before network awaits, and reopen before writing.
    {
        let (_db, repo) = open_wallet_db_for(&wallet_id)?;
        if let Some(payload) = repo.get_payment_disclosures(&wallet_id, network, &txid)? {
            let payload = Zeroizing::new(payload);
            let stored: StoredDisclosures = serde_json::from_slice(&payload)
                .map_err(|_| anyhow!("Invalid stored payment disclosures"))?;
            if stored.version == 1 && stored.recovery_keys == recovery_keys {
                validate_disclosure_bundle(&stored.outputs, &txid, network_type)?;
                return Ok(stored.outputs);
            }
            // Imported keys can recover additional outputs. Refresh rather
            // than permanently returning an old, partial recovery set.
        }
    }

    let raw = fetch(endpoint_config, tx_hash_candidates).await?;
    let tx = read_pirate_transaction(&raw.bytes)
        .map_err(|_| anyhow!("Cannot decode transaction for payment disclosure"))?;
    let txid_bytes = *tx.txid().as_ref();
    ensure_disclosure_txid_matches(&txid_string(&txid_bytes), &txid)?;
    let disclosures = recover_payment_disclosures_from_tx(
        &tx,
        &txid_bytes,
        raw.height.or(tx_height_hint),
        &sapling_ovks,
        &orchard_ovks,
        network_type,
    );
    // Empty recovery is not a durable negative result: new keys or corrected
    // height information can make outputs recoverable on a later attempt.
    if !disclosures.is_empty() {
        validate_disclosure_bundle(&disclosures, &txid, network_type)?;
        if wallet_network_type(&wallet_id)? != chain_network
            || address_prefix_network_type(&wallet_id)? != network_type
        {
            return Err(anyhow!(
                "Wallet network changed while recovering payment disclosures"
            ));
        }
        let (_db, repo) = open_wallet_db_for(&wallet_id)?;
        let payload = zeroize::Zeroizing::new(serde_json::to_vec(&StoredDisclosures {
            version: 1,
            recovery_keys,
            outputs: disclosures.clone(),
        })?);
        repo.put_payment_disclosures(&wallet_id, network, &txid, &payload)?;
    }
    Ok(disclosures)
}

fn disclosure_network_name(network: NetworkType) -> &'static str {
    match network {
        NetworkType::Mainnet => "mainnet",
        NetworkType::Testnet => "testnet",
        NetworkType::Regtest => "regtest",
    }
}

fn normalize_disclosure_txid(txid: &str) -> Result<String> {
    let bytes = hex::decode(txid).map_err(|_| anyhow!("Invalid transaction ID"))?;
    if bytes.len() != 32 {
        return Err(anyhow!("Invalid transaction ID length"));
    }
    Ok(hex::encode(bytes))
}

fn ensure_disclosure_txid_matches(actual: &str, requested: &str) -> Result<()> {
    let mut reverse = hex::decode(requested)?;
    reverse.reverse();
    // Preserve the service's legacy support for both transaction byte orders.
    if actual != requested && actual != hex::encode(reverse) {
        return Err(anyhow!("Payment disclosure transaction ID mismatch"));
    }
    Ok(())
}

fn validate_disclosure_bundle(
    disclosures: &[PaymentDisclosure],
    txid: &str,
    network: NetworkType,
) -> Result<()> {
    if disclosures.is_empty() {
        return Err(anyhow!("Empty stored payment disclosures"));
    }
    let mut outputs = HashSet::new();
    for disclosure in disclosures {
        ensure_disclosure_txid_matches(&disclosure.txid, txid)?;
        let decoded = decode_payment_disclosure(&disclosure.disclosure)?;
        if decoded.network_type != network
            || decoded.kind.as_str() != disclosure.disclosure_type
            || decoded.output_index != disclosure.output_index
            || txid_string(&decoded.txid_bytes) != disclosure.txid
            || !outputs.insert((disclosure.disclosure_type.as_str(), disclosure.output_index))
        {
            return Err(anyhow!("Invalid payment disclosure output binding"));
        }
    }
    Ok(())
}

/// Export a Sapling payment disclosure for a specific output index.
pub async fn export_sapling_payment_disclosure(
    wallet_id: WalletId,
    txid: String,
    output_index: u32,
) -> Result<String> {
    run_on_runtime(move || export_sapling_payment_disclosure_inner(wallet_id, txid, output_index))
        .await
}

async fn export_sapling_payment_disclosure_inner(
    wallet_id: WalletId,
    txid: String,
    output_index: u32,
) -> Result<String> {
    export_payment_disclosures_inner(wallet_id, txid)
        .await?
        .into_iter()
        .find(|d| {
            d.disclosure_type == DisclosureKind::Sapling.as_str() && d.output_index == output_index
        })
        .map(|d| d.disclosure)
        .ok_or_else(|| {
            anyhow!(
                "No Sapling payment disclosure found for output index {}",
                output_index
            )
        })
}

/// Export an Ironwood payment disclosure for a specific action index.
pub async fn export_ironwood_payment_disclosure(
    wallet_id: WalletId,
    txid: String,
    action_index: u32,
) -> Result<String> {
    run_on_runtime(move || export_ironwood_payment_disclosure_inner(wallet_id, txid, action_index))
        .await
}

async fn export_ironwood_payment_disclosure_inner(
    wallet_id: WalletId,
    txid: String,
    action_index: u32,
) -> Result<String> {
    export_payment_disclosures_inner(wallet_id, txid)
        .await?
        .into_iter()
        .find(|d| {
            d.disclosure_type == DisclosureKind::Ironwood.as_str() && d.output_index == action_index
        })
        .map(|d| d.disclosure)
        .ok_or_else(|| {
            anyhow!(
                "No Ironwood payment disclosure found for action index {}",
                action_index
            )
        })
}

/// Verify and decrypt a Sapling or Ironwood payment disclosure.
pub async fn verify_payment_disclosure(
    wallet_id: WalletId,
    disclosure: String,
) -> Result<PaymentDisclosureVerification> {
    run_on_runtime(move || verify_payment_disclosure_inner(wallet_id, disclosure)).await
}

async fn verify_payment_disclosure_inner(
    wallet_id: WalletId,
    disclosure: String,
) -> Result<PaymentDisclosureVerification> {
    let decoded = decode_payment_disclosure(&disclosure)?;
    let wallet_network = address_prefix_network_type(&wallet_id)?;
    if decoded.network_type != wallet_network {
        return Err(anyhow!(
            "Payment disclosure is for {:?}, but wallet endpoint is configured for {:?}",
            decoded.network_type,
            wallet_network
        ));
    }

    let endpoint_config = get_lightd_endpoint_config(wallet_id)?;
    let mut reversed = decoded.txid_bytes;
    reversed.reverse();
    let tx_hash_candidates = if reversed == decoded.txid_bytes {
        vec![decoded.txid_bytes]
    } else {
        vec![decoded.txid_bytes, reversed]
    };
    let raw = fetch_raw_transaction(endpoint_config, tx_hash_candidates).await?;
    let tx = read_pirate_transaction(raw.bytes.as_slice())
        .map_err(|e| anyhow!("Failed to parse transaction: {}", e))?;
    let txid_bytes = *tx.txid().as_ref();
    let ock = zcash_note_encryption::OutgoingCipherKey(decoded.ock);

    match decoded.kind {
        DisclosureKind::Sapling => {
            let bundle = tx
                .sapling_bundle()
                .ok_or_else(|| anyhow!("Transaction has no Sapling outputs"))?;
            let output = bundle
                .shielded_outputs()
                .get(decoded.output_index as usize)
                .ok_or_else(|| {
                    anyhow!("Sapling output index {} out of range", decoded.output_index)
                })?;
            let block_height = BlockHeight::from_u32(raw.height.unwrap_or(0));
            let network = PirateNetwork::new(wallet_network);
            let sapling_zip212 = zip212_enforcement(&network, block_height);
            let (note, address, memo) =
                try_sapling_output_recovery_with_ock(&ock, output, sapling_zip212)
                    .ok_or_else(|| anyhow!("Failed to decrypt Sapling output with disclosure"))?;
            let memo_vec = memo.to_vec();
            Ok(PaymentDisclosureVerification {
                disclosure_type: DisclosureKind::Sapling.as_str().to_string(),
                txid: txid_string(&txid_bytes),
                output_index: decoded.output_index,
                address: PaymentAddress { inner: address }.encode_for_network(wallet_network),
                amount: note.value().inner(),
                memo: memo_to_text(&memo_vec),
                memo_hex: hex::encode(memo_vec),
            })
        }
        DisclosureKind::Ironwood => {
            let bundle = tx
                .ironwood_bundle()
                .ok_or_else(|| anyhow!("Transaction has no Ironwood actions"))?;
            let action = bundle
                .actions()
                .get(decoded.output_index as usize)
                .ok_or_else(|| {
                    anyhow!(
                        "Ironwood action index {} out of range",
                        decoded.output_index
                    )
                })?;
            let domain = IronwoodDomain::for_action(action);
            let (note, address, memo) = try_output_recovery_with_ock(
                &domain,
                &ock,
                action,
                &action.encrypted_note().out_ciphertext,
            )
            .ok_or_else(|| anyhow!("Failed to decrypt Ironwood action with disclosure"))?;
            let memo_vec = memo.to_vec();
            let address = (IronwoodPaymentAddress { inner: address })
                .encode_for_network(wallet_network)
                .map_err(|e| anyhow!("Failed to encode Ironwood address: {}", e))?;
            Ok(PaymentDisclosureVerification {
                disclosure_type: DisclosureKind::Ironwood.as_str().to_string(),
                txid: txid_string(&txid_bytes),
                output_index: decoded.output_index,
                address,
                amount: note.value().inner(),
                memo: memo_to_text(&memo_vec),
                memo_hex: hex::encode(memo_vec),
            })
        }
    }
}

#[cfg(test)]
mod persistence_tests {
    use super::*;

    fn encrypted_sapling_fixture(ovk: SaplingOutgoingViewingKey) -> (String, Vec<u8>) {
        use sapling::note_encryption::{sapling_note_encryption, SaplingDomain};
        use sapling::value::{NoteValue, ValueCommitTrapdoor, ValueCommitment};
        use zcash_primitives::transaction::{Authorized, TransactionData, TxVersion};
        use zcash_protocol::consensus::BranchId;
        use zcash_protocol::value::ZatBalance;
        let mut rng = rand::rngs::OsRng;
        let key = sapling::zip32::ExtendedSpendingKey::master(&[5; 32]);
        let (_, address) = key.default_address();
        let value = NoteValue::from_raw(100);
        let cv = ValueCommitment::derive(value, ValueCommitTrapdoor::random(&mut rng));
        let enforcement = zip212_enforcement(
            &PirateNetwork::new(NetworkType::Mainnet),
            BlockHeight::from_u32(1_000_000),
        );
        let note = address.create_note(
            value,
            sapling::util::generate_random_rseed(enforcement, &mut rng),
        );
        let cmu = note.cmu();
        let encryption = sapling_note_encryption(Some(ovk), note, [0; 512], &mut rng);
        let output = sapling::bundle::OutputDescription::from_parts(
            cv.clone(),
            cmu,
            SaplingDomain::epk_bytes(encryption.epk()),
            encryption.encrypt_note_plaintext(),
            encryption.encrypt_outgoing_plaintext(&cv, &cmu, &mut rng),
            [0u8; 192],
        );
        // Real note encryption, with dummy proof/signature bytes: never broadcast.
        let bundle = sapling::Bundle::from_parts(
            vec![],
            vec![output],
            ZatBalance::from_i64(0).unwrap(),
            sapling::bundle::Authorized {
                binding_sig: [0u8; 64].into(),
            },
        );
        let tx = TransactionData::<Authorized>::from_parts(
            TxVersion::V4,
            BranchId::Sapling,
            0,
            BlockHeight::from_u32(1_000_020),
            None,
            None,
            bundle,
            None,
        )
        .freeze()
        .unwrap();
        let mut bytes = Vec::new();
        tx.write(&mut bytes).unwrap();
        (tx.txid().to_string(), bytes)
    }

    // Encoded fixtures exercise storage/binding, not validity of a chain payment.
    fn fixture(kind: DisclosureKind, network: NetworkType, index: u32) -> PaymentDisclosure {
        let bytes = [0x31; 32];
        PaymentDisclosure {
            disclosure_type: kind.as_str().to_owned(),
            txid: txid_string(&bytes),
            output_index: index,
            address: "test-fixture-recipient".into(),
            amount: 42,
            memo: Some("private fixture memo".into()),
            disclosure: encode_payment_disclosure(kind, network, &bytes, index, &[7; 32]).unwrap(),
        }
    }

    #[test]
    fn disclosure_binding_checks_network_transaction_pool_index_and_duplicates() {
        let one = SaplingOutgoingViewingKey([1; 32]);
        let two = SaplingOutgoingViewingKey([2; 32]);
        assert_ne!(
            recovery_key_fingerprint(&[one], &[]),
            recovery_key_fingerprint(&[one, two], &[])
        );
        assert_eq!(
            recovery_key_fingerprint(&[one, two], &[]),
            recovery_key_fingerprint(&[two, one], &[])
        );
        for network in [
            NetworkType::Mainnet,
            NetworkType::Testnet,
            NetworkType::Regtest,
        ] {
            let bundle = vec![
                fixture(DisclosureKind::Sapling, network, 0),
                fixture(DisclosureKind::Ironwood, network, 0),
            ];
            let txid = bundle[0].txid.clone();
            validate_disclosure_bundle(&bundle, &txid, network).unwrap();
            assert!(validate_disclosure_bundle(&bundle, &"12".repeat(32), network).is_err());
            let wrong_network = if network == NetworkType::Mainnet {
                NetworkType::Testnet
            } else {
                NetworkType::Mainnet
            };
            assert!(validate_disclosure_bundle(&bundle, &txid, wrong_network).is_err());
            let mut wrong = bundle.clone();
            wrong[0].output_index += 1;
            assert!(validate_disclosure_bundle(&wrong, &txid, network).is_err());
            wrong = bundle.clone();
            wrong[0].disclosure_type = "ironwood".into();
            assert!(validate_disclosure_bundle(&wrong, &txid, network).is_err());
            wrong = bundle.clone();
            wrong.push(bundle[0].clone());
            assert!(validate_disclosure_bundle(&wrong, &txid, network).is_err());
        }
        assert!(normalize_disclosure_txid("not-a-txid").is_err());
        assert!(normalize_disclosure_txid("00").is_err());
        assert!(validate_disclosure_bundle(&[], &"31".repeat(32), NetworkType::Mainnet).is_err());
    }

    #[test]
    fn disclosure_database_hit_works_offline_after_reopen_and_passphrase_change() {
        let _guard = GLOBAL_WALLET_STATE_TEST_MUTEX.lock().unwrap();
        reset_global_wallet_state_for_tests();
        struct Reset;
        impl Drop for Reset {
            fn drop(&mut self) {
                reset_global_wallet_state_for_tests();
            }
        }
        let _reset = Reset;
        let directory = tempfile::tempdir().unwrap();
        configure_wallet_storage(
            directory.path().to_string_lossy().into_owned(),
            "test-passphrase-123".into(),
        )
        .unwrap();
        let wallet_id =
            create_wallet("disclosure-test".into(), None, Some(1_000_000), None).unwrap();
        // A deliberately unreachable endpoint ensures no hit needs a server.
        set_lightd_endpoint(wallet_id.clone(), "http://127.0.0.1:1".into(), None).unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let (_, _, sapling, _, _) =
            collect_tx_recovery_context(&wallet_id, &"31".repeat(32)).unwrap();
        let (recovered_txid, raw) = encrypted_sapling_fixture(sapling[0]);
        let (unrecoverable_txid, unrecoverable_raw) =
            encrypted_sapling_fixture(SaplingOutgoingViewingKey([88; 32]));
        let empty = runtime
            .block_on(export_payment_disclosures_with_fetch(
                wallet_id.clone(),
                unrecoverable_txid.clone(),
                |_, _| async {
                    Ok(RawTransactionFetch {
                        bytes: unrecoverable_raw,
                        height: Some(1_000_000),
                    })
                },
            ))
            .unwrap();
        assert!(empty.is_empty());
        {
            let (_, repo) = open_wallet_db_for(&wallet_id).unwrap();
            assert!(repo
                .get_payment_disclosures(&wallet_id, "mainnet", &unrecoverable_txid)
                .unwrap()
                .is_none());
        }
        // Failed fetches and mismatched transactions must not poison the DB.
        let failed = runtime.block_on(export_payment_disclosures_with_fetch(
            wallet_id.clone(),
            recovered_txid.clone(),
            |_, _| async { Err(anyhow!("fixture offline")) },
        ));
        assert!(failed.is_err());
        let wrong_txid = "ab".repeat(32);
        let wrong = runtime.block_on(export_payment_disclosures_with_fetch(
            wallet_id.clone(),
            wrong_txid.clone(),
            |_, _| async {
                Ok(RawTransactionFetch {
                    bytes: raw.clone(),
                    height: Some(1_000_000),
                })
            },
        ));
        assert!(wrong.is_err());
        {
            let (_, repo) = open_wallet_db_for(&wallet_id).unwrap();
            assert!(repo
                .get_payment_disclosures(&wallet_id, "mainnet", &recovered_txid)
                .unwrap()
                .is_none());
            assert!(repo
                .get_payment_disclosures(&wallet_id, "mainnet", &wrong_txid)
                .unwrap()
                .is_none());
        }
        let recovered = runtime
            .block_on(export_payment_disclosures_with_fetch(
                wallet_id.clone(),
                recovered_txid.clone(),
                |_, _| async {
                    Ok(RawTransactionFetch {
                        bytes: raw,
                        height: Some(1_000_000),
                    })
                },
            ))
            .unwrap();
        assert_eq!(recovered.len(), 1);
        assert_eq!(recovered[0].amount, 100);
        encrypted_db::invalidate_all_wallet_db_caches();
        let persisted = runtime
            .block_on(export_payment_disclosures_with_fetch(
                wallet_id.clone(),
                recovered_txid,
                |_, _| async { panic!("persisted recovery must not fetch again") },
            ))
            .unwrap();
        assert_eq!(persisted[0].disclosure, recovered[0].disclosure);
        let bundle = vec![
            fixture(DisclosureKind::Sapling, NetworkType::Mainnet, 0),
            fixture(DisclosureKind::Ironwood, NetworkType::Mainnet, 0),
        ];
        let txid = bundle[0].txid.clone();
        {
            let (_db, repo) = open_wallet_db_for(&wallet_id).unwrap();
            let (_, _, sapling, ironwood, _) =
                collect_tx_recovery_context(&wallet_id, &txid).unwrap();
            repo.put_payment_disclosures(
                &wallet_id,
                "mainnet",
                &txid,
                &serde_json::to_vec(&StoredDisclosures {
                    version: 1,
                    recovery_keys: recovery_key_fingerprint(&sapling, &ironwood),
                    outputs: bundle.clone(),
                })
                .unwrap(),
            )
            .unwrap();
        }
        encrypted_db::invalidate_all_wallet_db_caches();
        let load = || {
            runtime.block_on(async {
                tokio::time::timeout(
                    Duration::from_secs(3),
                    export_payment_disclosures_inner(wallet_id.clone(), txid.clone()),
                )
                .await
                .expect("cache hit must not contact the server")
                .unwrap()
            })
        };
        assert_eq!(load().len(), 2);
        passphrase_store::clear_passphrase();
        assert!(runtime
            .block_on(export_payment_disclosures_inner(
                wallet_id.clone(),
                txid.clone()
            ))
            .is_err());
        unlock_app("test-passphrase-123".into()).unwrap();
        assert_eq!(load()[0].disclosure, bundle[0].disclosure);
        encrypted_db::change_app_passphrase(
            "test-passphrase-123".into(),
            "changed-passphrase-456".into(),
        )
        .unwrap();
        encrypted_db::invalidate_all_wallet_db_caches();
        assert_eq!(load()[1].disclosure, bundle[1].disclosure);
    }
}
