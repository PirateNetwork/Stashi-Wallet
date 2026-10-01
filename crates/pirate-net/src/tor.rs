//! Tor configuration and optional embedded client integration.

use directories::{BaseDirs, ProjectDirs};
use std::env;
use std::path::PathBuf;
use std::time::Duration;

const TOR_STATE_DIR_ENV: &str = "PIRATE_TOR_STATE_DIR";
const TOR_CACHE_DIR_ENV: &str = "PIRATE_TOR_CACHE_DIR";
const TOR_BASE_DIR_ENV: &str = "PIRATE_TOR_DIR";
const WALLET_DB_DIR_ENV: &str = "PIRATE_WALLET_DB_DIR";

/// Tor bootstrap status
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TorStatus {
    /// Not started
    NotStarted,
    /// Bootstrapping with progress (0-100) and optional blockage message
    Bootstrapping {
        /// Percent ready (best effort)
        progress: u8,
        /// Optional blockage hint from Arti
        blocked: Option<String>,
    },
    /// Ready for connections
    Ready,
    /// Error state with message
    Error(String),
}

/// Pluggable transport selection for bridges
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TorBridgeTransport {
    /// obfs4 transport
    Obfs4,
    /// snowflake transport
    Snowflake,
    /// Custom transport name
    Custom(String),
}

/// Bridge configuration for censorship circumvention
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TorBridgeConfig {
    /// Selected transport
    pub transport: TorBridgeTransport,
    /// Bridge lines (one per entry)
    pub bridge_lines: Vec<String>,
    /// Path to PT client binary (optional; falls back to name on PATH)
    pub transport_path: Option<PathBuf>,
}

/// Tor client configuration
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TorConfig {
    /// Enable Tor
    pub enabled: bool,
    /// Tor state directory
    pub state_dir: PathBuf,
    /// Tor cache directory
    pub cache_dir: PathBuf,
    /// Enable debug logging
    pub debug: bool,
    /// Bootstrap timeout
    pub bootstrap_timeout: Duration,
    /// Stream connection timeout
    pub connect_timeout: Duration,
    /// Use bridges immediately when bootstrapping
    pub use_bridges: bool,
    /// Retry with bridges if direct bootstrap fails
    pub fallback_to_bridges: bool,
    /// Bridge configuration (required for bridge usage)
    pub bridges: Option<TorBridgeConfig>,
}

impl Default for TorConfig {
    fn default() -> Self {
        let (state_dir, cache_dir) = default_tor_dirs();
        Self {
            enabled: true,
            state_dir,
            cache_dir,
            debug: false,
            bootstrap_timeout: Duration::from_secs(120),
            connect_timeout: Duration::from_secs(30),
            use_bridges: false,
            fallback_to_bridges: true,
            bridges: None,
        }
    }
}

fn tor_base_candidates() -> Vec<PathBuf> {
    let mut bases = Vec::new();

    if let Some(base) = non_empty_env_path(TOR_BASE_DIR_ENV) {
        bases.push(base);
    }
    if let Some(wallet_dir) = non_empty_env_path(WALLET_DB_DIR_ENV) {
        let candidate = wallet_dir.join("tor");
        if !bases.iter().any(|path| path == &candidate) {
            bases.push(candidate);
        }
    }
    if let Some(dirs) = ProjectDirs::from("com", "Pirate", "PirateWallet") {
        let candidate = dirs.data_local_dir().join("tor");
        if !bases.iter().any(|path| path == &candidate) {
            bases.push(candidate);
        }
    }
    if let Some(base) = BaseDirs::new() {
        let candidate = base.data_local_dir().join("PirateWallet").join("tor");
        if !bases.iter().any(|path| path == &candidate) {
            bases.push(candidate);
        }
    }
    if let Ok(home) = env::var("HOME") {
        if !home.trim().is_empty() {
            let candidate = PathBuf::from(home).join(".pirate_wallet").join("tor");
            if !bases.iter().any(|path| path == &candidate) {
                bases.push(candidate);
            }
        }
    }

    bases.push(env::temp_dir().join("pirate_wallet").join("tor"));
    bases
}

fn non_empty_env_path(name: &str) -> Option<PathBuf> {
    env::var_os(name)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

fn resolve_tor_dirs(
    fallback_base: PathBuf,
    state_override: Option<PathBuf>,
    cache_override: Option<PathBuf>,
) -> (PathBuf, PathBuf) {
    let state_dir = state_override.unwrap_or_else(|| fallback_base.join("state"));
    let cache_dir = cache_override.unwrap_or_else(|| fallback_base.join("cache"));
    (state_dir, cache_dir)
}

fn default_tor_dirs() -> (PathBuf, PathBuf) {
    let base = tor_base_candidates()
        .into_iter()
        .next()
        .unwrap_or_else(|| env::temp_dir().join("pirate_wallet").join("tor"));
    resolve_tor_dirs(
        base,
        non_empty_env_path(TOR_STATE_DIR_ENV),
        non_empty_env_path(TOR_CACHE_DIR_ENV),
    )
}

#[cfg(feature = "embedded-tor")]
mod embedded;
#[cfg(not(feature = "embedded-tor"))]
mod unavailable;

#[cfg(feature = "embedded-tor")]
pub use embedded::TorClient;
#[cfg(not(feature = "embedded-tor"))]
pub use unavailable::{TorClient, UnavailableTorStream};
