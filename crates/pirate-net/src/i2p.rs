//! I2P configuration and optional embedded router integration.

use std::path::PathBuf;
use std::time::Duration;

/// I2P bootstrap status
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum I2pStatus {
    /// Not started
    NotStarted,
    /// Starting router
    Starting,
    /// Ready for connections
    Ready,
    /// Error state with message
    Error(String),
}

/// I2P router configuration (desktop only)
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct I2pConfig {
    /// Enable I2P
    pub enabled: bool,
    /// Optional path to embedded i2pd binary
    pub binary_path: Option<PathBuf>,
    /// Optional persistent data dir (ignored if ephemeral)
    pub data_dir: Option<PathBuf>,
    /// Router listens on this address
    pub address: String,
    /// SOCKS proxy port
    pub socks_port: u16,
    /// Use ephemeral router state (new data dir per launch).
    ///
    /// Persistent state is the production default because discarding i2pd's
    /// network database on every launch can make the router unusable for many
    /// minutes. The router identity is not an application destination key.
    pub ephemeral: bool,
    /// Router startup timeout
    pub startup_timeout: Duration,
    /// Extra CLI arguments to pass to i2pd
    pub extra_args: Vec<String>,
}

impl Default for I2pConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            binary_path: None,
            data_dir: None,
            address: "127.0.0.1".to_string(),
            socks_port: 4447,
            ephemeral: false,
            startup_timeout: Duration::from_secs(180),
            extra_args: Vec::new(),
        }
    }
}

#[cfg(feature = "embedded-i2p")]
mod embedded;
#[cfg(not(feature = "embedded-i2p"))]
mod unavailable;

#[cfg(feature = "embedded-i2p")]
pub use embedded::I2pClient;
#[cfg(not(feature = "embedded-i2p"))]
pub use unavailable::I2pClient;
