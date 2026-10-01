//! Fail-closed API for builds that omit the embedded I2P router.

use super::{I2pConfig, I2pStatus};
use crate::{Error, Result, Socks5Config};
use std::sync::Arc;
use tokio::sync::{Mutex, OwnedMutexGuard};

/// Unavailable I2P client for builds that omit the embedded router.
///
/// Construction always returns an explicit error, so no router process or
/// proxy connection can be created through this implementation.
#[derive(Clone)]
pub struct I2pClient {
    config: Arc<Mutex<I2pConfig>>,
    connect_lock: Arc<Mutex<()>>,
}

impl I2pClient {
    /// Return an error because this build omits embedded I2P.
    pub fn new(_config: I2pConfig) -> Result<Self> {
        Err(Error::EmbeddedI2pUnavailable)
    }

    /// Updating configuration cannot enable an omitted implementation.
    pub async fn update_config(self, config: I2pConfig) {
        *self.config.lock().await = config;
    }

    /// Return an error without starting a router process.
    pub async fn start(self) -> Result<()> {
        Err(Error::EmbeddedI2pUnavailable)
    }

    /// Report that embedded I2P is unavailable.
    pub async fn status(self) -> I2pStatus {
        I2pStatus::Error(Error::EmbeddedI2pUnavailable.to_string())
    }

    /// An omitted implementation is never ready.
    pub async fn is_ready(self) -> bool {
        false
    }

    /// Retain the configured proxy description without creating a connection.
    pub async fn proxy_config(self) -> Socks5Config {
        let config = self.config.lock().await;
        Socks5Config {
            host: config.address.clone(),
            port: config.socks_port,
            username: None,
            password: None,
        }
    }

    pub(crate) async fn connection_guard(self) -> OwnedMutexGuard<()> {
        self.connect_lock.lock_owned().await
    }

    /// An omitted implementation has no resources to shut down.
    pub async fn shutdown(self) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unavailable_i2p_cannot_create_a_router() {
        assert!(matches!(
            I2pClient::new(I2pConfig {
                enabled: true,
                ..I2pConfig::default()
            }),
            Err(Error::EmbeddedI2pUnavailable)
        ));
    }

    #[tokio::test]
    async fn unavailable_i2p_status_never_reports_ready() {
        let client = I2pClient {
            config: Arc::new(Mutex::new(I2pConfig::default())),
            connect_lock: Arc::new(Mutex::new(())),
        };
        assert!(matches!(
            client.clone().start().await,
            Err(Error::EmbeddedI2pUnavailable)
        ));
        assert!(!client.clone().is_ready().await);
        assert_eq!(
            client.clone().status().await,
            I2pStatus::Error(Error::EmbeddedI2pUnavailable.to_string())
        );
        client.clone().update_config(I2pConfig::default()).await;
        client.clone().shutdown().await;
        assert!(!client.is_ready().await);
    }
}
