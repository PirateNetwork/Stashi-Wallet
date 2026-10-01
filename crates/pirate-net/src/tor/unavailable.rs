//! Fail-closed API for builds that omit embedded Tor.

use super::{TorConfig, TorStatus};
use crate::{Error, Result};
use std::io;
use std::pin::Pin;
use std::task::{Context, Poll};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

/// An uninhabited stream type returned when embedded Tor is unavailable.
///
/// It implements the stream traits for callers shared with embedded builds,
/// but no stream can be constructed and connection methods always fail.
#[derive(Debug)]
pub enum UnavailableTorStream {}

impl AsyncRead for UnavailableTorStream {
    fn poll_read(
        self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        _buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        match *self.get_mut() {}
    }
}

impl AsyncWrite for UnavailableTorStream {
    fn poll_write(
        self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        _buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        match *self.get_mut() {}
    }

    fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        match *self.get_mut() {}
    }

    fn poll_shutdown(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        match *self.get_mut() {}
    }
}

/// Unavailable embedded Tor client. All connection operations fail explicitly.
#[derive(Clone, Default)]
pub struct TorClient {
    _unavailable: (),
}

impl TorClient {
    /// Return an error because this build omits embedded Tor.
    pub fn new(_config: TorConfig) -> Result<Self> {
        Err(Error::EmbeddedTorUnavailable)
    }

    /// Updating configuration cannot enable an omitted implementation.
    pub async fn update_config(self, _config: TorConfig) {}

    /// Return an error without starting a network task.
    pub async fn bootstrap(self) -> Result<()> {
        Err(Error::EmbeddedTorUnavailable)
    }

    /// Report that embedded Tor is unavailable.
    pub async fn status(&self) -> TorStatus {
        TorStatus::Error(Error::EmbeddedTorUnavailable.to_string())
    }

    /// Report that embedded Tor is unavailable from an owned handle.
    pub async fn status_owned(self) -> TorStatus {
        self.status().await
    }

    /// An omitted implementation is never ready.
    pub async fn is_ready(&self) -> bool {
        false
    }

    /// Reject a stream request without opening a connection.
    pub async fn connect_stream(&self, _host: &str, _port: u16) -> Result<UnavailableTorStream> {
        Err(Error::EmbeddedTorUnavailable)
    }

    /// Reject an owned stream request without opening a connection.
    pub async fn connect_stream_owned(
        self,
        _host: String,
        _port: u16,
    ) -> Result<UnavailableTorStream> {
        Err(Error::EmbeddedTorUnavailable)
    }

    /// An omitted implementation has no circuits to rotate.
    pub async fn rotate_exit(&self) {}

    /// Reject an exit address request without opening a connection.
    pub async fn fetch_exit_ip(self) -> Result<String> {
        Err(Error::EmbeddedTorUnavailable)
    }

    /// An omitted implementation has no resources to shut down.
    pub async fn shutdown(self) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn unavailable_tor_never_becomes_ready_or_connects() {
        assert!(matches!(
            TorClient::new(TorConfig::default()),
            Err(Error::EmbeddedTorUnavailable)
        ));
        let client = TorClient::default();
        assert!(!client.is_ready().await);
        assert_eq!(
            client.status().await,
            TorStatus::Error(Error::EmbeddedTorUnavailable.to_string())
        );
        assert!(matches!(
            client.clone().bootstrap().await,
            Err(Error::EmbeddedTorUnavailable)
        ));
        assert!(matches!(
            client.connect_stream("127.0.0.1", 1).await,
            Err(Error::EmbeddedTorUnavailable)
        ));
        assert!(matches!(
            client
                .clone()
                .connect_stream_owned("localhost".into(), 1)
                .await,
            Err(Error::EmbeddedTorUnavailable)
        ));
        assert!(matches!(
            client.clone().fetch_exit_ip().await,
            Err(Error::EmbeddedTorUnavailable)
        ));
        client.clone().update_config(TorConfig::default()).await;
        client.clone().shutdown().await;
        assert!(!client.is_ready().await);
        assert!(matches!(client.status().await, TorStatus::Error(_)));
    }
}
