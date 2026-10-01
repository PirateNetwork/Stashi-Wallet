//! Error types

/// Network errors
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// Embedded Tor support was omitted from this build.
    #[error("Embedded Tor is unavailable in this build (enable the embedded-tor feature)")]
    EmbeddedTorUnavailable,

    /// Embedded I2P support was omitted from this build.
    #[error("Embedded I2P is unavailable in this build (enable the embedded-i2p feature)")]
    EmbeddedI2pUnavailable,

    /// Tor error
    #[error("Tor error: {0}")]
    Tor(String),

    /// DNS error
    #[error("DNS error: {0}")]
    Dns(String),

    /// TLS error
    #[error("TLS error: {0}")]
    Tls(String),

    /// Connection error
    #[error("Connection error: {0}")]
    Connection(String),

    /// Network error
    #[error("Network error: {0}")]
    Network(String),

    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

/// Result type
pub type Result<T> = std::result::Result<T, Error>;
