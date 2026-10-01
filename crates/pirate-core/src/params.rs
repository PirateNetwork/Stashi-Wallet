//! zk-SNARK parameter loading for Sapling and Ironwood.
//!
//! - Default builds embed Sapling parameters. Compact SDK builds accept verified
//!   parameter files supplied by their host through [`initialize_sapling_parameters`].
//!   No network access or default filesystem search occurs here.
//! - Ironwood proving/verification keys are constructed in-memory via
//!   `orchard::circuit`.
//!
//! The parameters are initialised lazily and cached for reuse.

#[cfg(feature = "embedded-sapling-params")]
use bellman::groth16::{Parameters, PreparedVerifyingKey};
#[cfg(feature = "embedded-sapling-params")]
use bls12_381::Bls12;
use once_cell::sync::OnceCell;
use sha2::{Digest, Sha256};
use std::fs::File;
#[cfg(feature = "embedded-sapling-params")]
use std::io::Cursor;
use std::io::Read;
use std::path::Path;
#[cfg(feature = "embedded-sapling-params")]
use std::sync::Arc;
use zcash_proofs::prover::LocalTxProver;

use crate::{Error, Result};

use orchard::circuit::{
    OrchardCircuitVersion, ProvingKey as OrchardProvingKey, VerifyingKey as OrchardVerifyingKey,
};

/// Cached Sapling proving and verifying parameters.
#[cfg(feature = "embedded-sapling-params")]
pub struct SaplingParams {
    /// Sapling spend proving parameters.
    pub spend_params: Arc<Parameters<Bls12>>,
    /// Sapling output proving parameters.
    pub output_params: Arc<Parameters<Bls12>>,
    /// Prepared spend verifying key.
    pub spend_vk: Arc<PreparedVerifyingKey<Bls12>>,
    /// Prepared output verifying key.
    pub output_vk: Arc<PreparedVerifyingKey<Bls12>>,
}

/// Cached Ironwood proving and verifying parameters.
pub struct IronwoodParams {
    /// Ironwood proving key (constructed in-memory).
    pub proving_key: OrchardProvingKey,
    /// Ironwood verifying key (constructed in-memory).
    pub verifying_key: OrchardVerifyingKey,
}

#[cfg(feature = "embedded-sapling-params")]
fn load_sapling_params() -> SaplingParams {
    let (spend_bytes, output_bytes) = wagyu_zcash_parameters::load_sapling_parameters();

    let spend_params = Parameters::<Bls12>::read(&mut Cursor::new(spend_bytes), false)
        .expect("couldn't deserialize Sapling spend parameters");
    let output_params = Parameters::<Bls12>::read(&mut Cursor::new(output_bytes), false)
        .expect("couldn't deserialize Sapling output parameters");

    // Prepare verifying keys for efficient verification
    use bellman::groth16::prepare_verifying_key;
    let spend_vk = prepare_verifying_key(&spend_params.vk);
    let output_vk = prepare_verifying_key(&output_params.vk);

    SaplingParams {
        spend_params: Arc::new(spend_params),
        output_params: Arc::new(output_params),
        spend_vk: Arc::new(spend_vk),
        output_vk: Arc::new(output_vk),
    }
}

fn load_ironwood_params() -> IronwoodParams {
    let circuit_version = OrchardCircuitVersion::PostNu6_3;
    let proving_key = OrchardProvingKey::build(circuit_version);
    let verifying_key = OrchardVerifyingKey::build(circuit_version);

    IronwoodParams {
        proving_key,
        verifying_key,
    }
}

/// Get shared Sapling parameters (lazy init).
#[cfg(feature = "embedded-sapling-params")]
pub fn sapling_params() -> &'static SaplingParams {
    static CELL: OnceCell<SaplingParams> = OnceCell::new();
    CELL.get_or_init(load_sapling_params)
}

/// Get shared Ironwood parameters (lazy init).
pub fn ironwood_params() -> &'static IronwoodParams {
    static CELL: OnceCell<IronwoodParams> = OnceCell::new();
    CELL.get_or_init(load_ironwood_params)
}

/// Build a `LocalTxProver` directly from the embedded Sapling parameters.
///
/// Keeping this path entirely in memory avoids platform-specific temporary
/// directory behavior and leaves no proving-parameter files behind on disk.
///
/// New transaction code should use [`try_sapling_prover`] to reuse the shared
/// prover and report parameter-loading failures without panicking.
#[cfg(feature = "embedded-sapling-params")]
pub fn sapling_prover() -> LocalTxProver {
    let (spend_bytes, output_bytes) = wagyu_zcash_parameters::load_sapling_parameters();
    LocalTxProver::from_bytes(&spend_bytes, &output_bytes)
}

// Canonical Sapling MPC parameter files. Validate the complete files, including
// the contribution transcript, before allowing the upstream parser to read them.
const SPEND_BYTES: u64 = 47_958_396;
const OUTPUT_BYTES: u64 = 3_592_860;
const SPEND_SHA256: &str = "8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13";
const OUTPUT_SHA256: &str = "2f0ebbcbb9bb0bcffe95a397e7eba89c29eb4dde6191c339db88570e3f3fb0e4";

#[derive(Default)]
struct SaplingProverCache {
    prover: OnceCell<LocalTxProver>,
}

impl SaplingProverCache {
    fn initialize(&self, spend_path: &Path, output_path: &Path) -> Result<()> {
        self.prover.get_or_try_init(|| {
            let spend = read_parameters(spend_path, "spend", SPEND_BYTES, SPEND_SHA256)?;
            let output = read_parameters(output_path, "output", OUTPUT_BYTES, OUTPUT_SHA256)?;
            parse_prover(&spend, &output)
        })?;
        Ok(())
    }

    fn get(&self) -> Result<&LocalTxProver> {
        #[cfg(feature = "embedded-sapling-params")]
        {
            self.prover.get_or_try_init(|| {
                let (spend, output) = wagyu_zcash_parameters::load_sapling_parameters();
                validate_parameters(&spend, "spend", SPEND_BYTES, SPEND_SHA256)?;
                validate_parameters(&output, "output", OUTPUT_BYTES, OUTPUT_SHA256)?;
                parse_prover(&spend, &output)
            })
        }
        #[cfg(not(feature = "embedded-sapling-params"))]
        {
            self.prover.get().ok_or_else(|| Error::SaplingParameters(
                "Initialize the verified Sapling spend and output parameter files before building a transaction".to_string(),
            ))
        }
    }
}

static SAPLING_PROVER: SaplingProverCache = SaplingProverCache {
    prover: OnceCell::new(),
};

/// Validate host-supplied parameter files and initialize the process-wide prover.
///
/// Compact builds must call this before building transactions. Default builds
/// can also supply files before their first transaction; otherwise the embedded
/// parameters are used. The host controls downloading and storage.
///
/// Initialization is synchronized, failures can be retried, and a successful
/// initialization is immutable and idempotent. After success neither the files
/// nor their paths are retained or used by later transactions.
pub fn initialize_sapling_parameters(spend_path: &Path, output_path: &Path) -> Result<()> {
    SAPLING_PROVER.initialize(spend_path, output_path)
}

/// Get the shared Sapling prover without reparsing parameters for every send.
///
/// Default builds initialize lazily from embedded parameters. Compact builds
/// return a recoverable error until [`initialize_sapling_parameters`] succeeds.
pub fn try_sapling_prover() -> Result<&'static LocalTxProver> {
    SAPLING_PROVER.get()
}

fn read_parameters(path: &Path, name: &str, size: u64, hash: &str) -> Result<Vec<u8>> {
    let file = File::open(path).map_err(|e| {
        Error::SaplingParameters(format!("Unable to open Sapling {name} parameters: {e}"))
    })?;
    let metadata = file.metadata().map_err(|e| {
        Error::SaplingParameters(format!("Unable to inspect Sapling {name} parameters: {e}"))
    })?;
    if !metadata.is_file() || metadata.len() != size {
        return Err(Error::SaplingParameters(format!(
            "Sapling {name} parameters must be a regular file containing exactly {size} bytes"
        )));
    }
    // Read at most the canonical size plus one, including when a file changes
    // after metadata inspection. Hash and parse the same bounded in-memory bytes.
    let mut bytes = Vec::with_capacity(size as usize);
    file.take(size + 1).read_to_end(&mut bytes).map_err(|e| {
        Error::SaplingParameters(format!("Unable to read Sapling {name} parameters: {e}"))
    })?;
    validate_parameters(&bytes, name, size, hash)?;
    Ok(bytes)
}

fn validate_parameters(bytes: &[u8], name: &str, size: u64, hash: &str) -> Result<()> {
    if bytes.len() as u64 != size {
        return Err(Error::SaplingParameters(format!(
            "Sapling {name} parameter length does not match the canonical file"
        )));
    }
    if hex::encode(Sha256::digest(bytes)) != hash {
        return Err(Error::SaplingParameters(format!(
            "Sapling {name} parameter checksum does not match the canonical file"
        )));
    }
    Ok(())
}

fn parse_prover(spend: &[u8], output: &[u8]) -> Result<LocalTxProver> {
    // Upstream exposes only a panicking constructor. Inputs have already passed
    // canonical length/hash checks, but an unexpected parser panic must still
    // become a recoverable SDK error instead of crossing its FFI boundary.
    std::panic::catch_unwind(|| LocalTxProver::from_bytes(spend, output)).map_err(|_| {
        Error::SaplingParameters("Unable to parse verified Sapling parameters".to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::rngs::OsRng;
    use sapling::prover::OutputProver;
    use sapling::value::{NoteValue, ValueCommitTrapdoor, ValueCommitment};
    use std::io::Write;
    use std::sync::Arc;

    fn canonical_bytes() -> &'static (Vec<u8>, Vec<u8>) {
        static BYTES: OnceCell<(Vec<u8>, Vec<u8>)> = OnceCell::new();
        BYTES.get_or_init(wagyu_zcash_parameters::load_sapling_parameters)
    }

    #[cfg(feature = "embedded-sapling-params")]
    #[test]
    fn embedded_prover_is_reused() {
        assert!(std::ptr::eq(
            try_sapling_prover().unwrap(),
            try_sapling_prover().unwrap()
        ));
    }

    #[cfg(not(feature = "embedded-sapling-params"))]
    #[test]
    fn compact_build_reports_missing_parameters() {
        let cache = SaplingProverCache::default();
        assert!(matches!(cache.get(), Err(Error::SaplingParameters(_))));
        assert!(cache.prover.get().is_none());
    }

    #[test]
    fn canonical_embedded_files_match_pinned_hashes() {
        let (spend, output) = canonical_bytes();
        validate_parameters(spend, "spend", SPEND_BYTES, SPEND_SHA256).unwrap();
        validate_parameters(output, "output", OUTPUT_BYTES, OUTPUT_SHA256).unwrap();
        let mut corrupted = output.clone();
        corrupted[0] ^= 1;
        assert!(validate_parameters(&corrupted, "output", OUTPUT_BYTES, OUTPUT_SHA256).is_err());
    }

    #[test]
    fn external_files_reject_invalid_inputs_then_initialize_once_and_prove() {
        let directory = tempfile::tempdir().unwrap();
        let spend_path = directory.path().join("sapling-spend.params");
        let output_path = directory.path().join("sapling-output.params");
        let cache = Arc::new(SaplingProverCache::default());

        // A missing or truncated download does not poison initialization.
        assert!(cache.initialize(&spend_path, &output_path).is_err());
        std::fs::write(&spend_path, b"partial download").unwrap();
        assert!(cache.initialize(&spend_path, &output_path).is_err());
        assert!(cache.prover.get().is_none());

        let (spend, output) = canonical_bytes();
        std::fs::write(&spend_path, spend).unwrap();
        std::fs::write(&output_path, output).unwrap();
        assert!(cache.initialize(&output_path, &spend_path).is_err());

        // Corruption with the correct file size must fail the hash check.
        let mut corrupted_output = File::options().write(true).open(&output_path).unwrap();
        corrupted_output.write_all(&[output[0] ^ 1]).unwrap();
        drop(corrupted_output);
        let error = cache.initialize(&spend_path, &output_path).err().unwrap();
        assert!(error.to_string().contains("checksum"));
        assert!(cache.prover.get().is_none());
        std::fs::write(&output_path, output).unwrap();

        // Concurrent hosts share one initialized prover; no second parse occurs.
        std::thread::scope(|scope| {
            let workers = (0..4)
                .map(|_| {
                    let cache = &cache;
                    let spend_path = &spend_path;
                    let output_path = &output_path;
                    scope.spawn(move || {
                        cache.initialize(spend_path, output_path).unwrap();
                        cache.get().unwrap() as *const LocalTxProver as usize
                    })
                })
                .collect::<Vec<_>>();
            let addresses = workers
                .into_iter()
                .map(|worker| worker.join().unwrap())
                .collect::<Vec<_>>();
            assert!(addresses.windows(2).all(|pair| pair[0] == pair[1]));
        });

        // Proving uses cached parameters even after their source files disappear.
        std::fs::remove_file(&spend_path).unwrap();
        std::fs::remove_file(&output_path).unwrap();
        cache.initialize(&spend_path, &output_path).unwrap();
        let prover = cache.get().unwrap();
        let mut rng = OsRng;
        let address = sapling::zip32::ExtendedSpendingKey::master(&[7; 32])
            .default_address()
            .1;
        let value = NoteValue::from_raw(123_000);
        let note = address.create_note(value, sapling::Rseed::AfterZip212([9; 32]));
        let esk = note.generate_or_derive_esk(&mut rng);
        let rcv = ValueCommitTrapdoor::random(&mut rng);
        let cv = ValueCommitment::derive(value, rcv.clone());
        let circuit =
            <LocalTxProver as OutputProver>::prepare_circuit(&esk, address, note.rcm(), value, rcv);
        let epk = (address.diversifier().g_d().unwrap() * circuit.esk.unwrap()).into();
        let proof = OutputProver::create_proof(prover, circuit, &mut rng);
        let (_, verifying_key) = prover.verifying_keys();
        assert!(sapling::SaplingVerificationContext::new().check_output(
            &cv,
            note.cmu(),
            epk,
            proof,
            &verifying_key.prepare(),
        ));
    }
}
