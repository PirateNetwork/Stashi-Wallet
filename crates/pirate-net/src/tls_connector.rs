//! Verified TLS for streams that have already been routed through a transport.

use crate::{Error, Result};
use rustls::{ClientConfig, RootCertStore};
use rustls_pki_types::ServerName;
use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio_rustls::{client::TlsStream, TlsConnector};

fn connector_with_roots(roots: RootCertStore) -> Result<TlsConnector> {
    // Select ring explicitly rather than changing the host's global provider.
    let config =
        ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
            .with_safe_default_protocol_versions()
            .map_err(|e| Error::Tls(format!("TLS connector build failed: {}", e)))?
            .with_root_certificates(roots)
            .with_no_client_auth();
    // Leave ALPN unset, as these streams carry HTTP/1.1 or certificate probes.
    // In particular, the manual HTTP/1.1 client must never negotiate HTTP/2.
    Ok(TlsConnector::from(Arc::new(config)))
}

fn webpki_connector() -> Result<TlsConnector> {
    let roots = RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    connector_with_roots(roots)
}

async fn connect_with<S>(
    connector: TlsConnector,
    server_name: &str,
    stream: S,
) -> Result<TlsStream<S>>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let name = ServerName::try_from(server_name.to_owned())
        .map_err(|e| Error::Tls(format!("Invalid TLS server name: {}", e)))?;
    connector
        .connect(name, stream)
        .await
        .map_err(|e| Error::Tls(format!("TLS handshake failed: {}", e)))
}

pub(crate) async fn connect_tls<S>(server_name: &str, stream: S) -> Result<TlsStream<S>>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    connect_with(webpki_connector()?, server_name, stream).await
}

pub(crate) fn peer_certificate_der<S>(stream: &TlsStream<S>) -> Result<Vec<u8>> {
    stream
        .get_ref()
        .1
        .peer_certificates()
        .and_then(|certs| certs.first())
        .map(|cert| cert.as_ref().to_vec())
        .ok_or_else(|| Error::Tls("No peer certificate presented".to_owned()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lightwalletd_pins::extract_spki_from_cert_der;
    use crate::{Socks5Config, TransportConfig, TransportManager, TransportMode};
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    use rcgen::{
        BasicConstraints, CertificateParams, ExtendedKeyUsagePurpose, IsCa, KeyPair,
        KeyUsagePurpose,
    };
    use rustls::ServerConfig;
    use rustls_pki_types::{CertificateDer, PrivatePkcs8KeyDer};
    use sha2::{Digest, Sha256};
    use std::net::SocketAddr;
    use std::time::Duration;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::{TcpListener, TcpStream};
    use tokio::task::JoinHandle;
    use tokio_rustls::TlsAcceptor;

    const TEST_TIMEOUT: Duration = Duration::from_secs(5);

    struct TestServer {
        config: Arc<ServerConfig>,
        ca: CertificateDer<'static>,
        leaf: CertificateDer<'static>,
        spki: String,
    }

    fn test_server(expired: bool) -> TestServer {
        let ca_key = KeyPair::generate().unwrap();
        let mut ca_params = CertificateParams::default();
        ca_params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        ca_params.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];
        ca_params.not_before = rcgen::date_time_ymd(2000, 1, 1);
        ca_params.not_after = rcgen::date_time_ymd(2100, 1, 1);
        let ca = ca_params.self_signed(&ca_key).unwrap();

        let leaf_key = KeyPair::generate().unwrap();
        let mut leaf_params = CertificateParams::new(vec!["localhost".to_owned()]).unwrap();
        leaf_params.key_usages = vec![KeyUsagePurpose::DigitalSignature];
        leaf_params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ServerAuth];
        leaf_params.not_before = rcgen::date_time_ymd(2000, 1, 1);
        leaf_params.not_after = rcgen::date_time_ymd(if expired { 2001 } else { 2100 }, 1, 1);
        let leaf = leaf_params.signed_by(&leaf_key, &ca, &ca_key).unwrap();

        let mut config =
            ServerConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
                .with_safe_default_protocol_versions()
                .unwrap()
                .with_no_client_auth()
                .with_single_cert(
                    vec![leaf.der().clone(), ca.der().clone()],
                    PrivatePkcs8KeyDer::from(leaf_key.serialize_der()).into(),
                )
                .unwrap();
        config.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];
        TestServer {
            config: Arc::new(config),
            ca: ca.der().clone(),
            leaf: leaf.der().clone(),
            spki: STANDARD.encode(Sha256::digest(leaf_key.public_key_der())),
        }
    }

    fn trusted_connector(server: &TestServer) -> TlsConnector {
        let mut roots = RootCertStore::empty();
        roots.add(server.ca.clone()).unwrap();
        connector_with_roots(roots).unwrap()
    }

    async fn listen(
        server: &TestServer,
    ) -> (SocketAddr, JoinHandle<std::io::Result<Option<String>>>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let acceptor = TlsAcceptor::from(server.config.clone());
        let task = tokio::spawn(async move {
            tokio::time::timeout(TEST_TIMEOUT, async move {
                let (stream, _) = listener.accept().await?;
                let stream = acceptor.accept(stream).await?;
                assert_eq!(stream.get_ref().1.alpn_protocol(), None);
                Ok(stream.get_ref().1.server_name().map(str::to_owned))
            })
            .await
            .expect("loopback TLS server timed out")
        });
        (addr, task)
    }

    async fn handshake(
        server: &TestServer,
        connector: TlsConnector,
        name: &str,
    ) -> (Result<Vec<u8>>, std::io::Result<Option<String>>) {
        let (addr, task) = listen(server).await;
        let result = tokio::time::timeout(TEST_TIMEOUT, async {
            let tcp = TcpStream::connect(addr).await.unwrap();
            let tls = connect_with(connector, name, tcp).await?;
            peer_certificate_der(&tls)
        })
        .await
        .expect("loopback TLS client timed out");
        (result, task.await.unwrap())
    }

    #[tokio::test]
    async fn trusted_tls_preserves_server_name_leaf_certificate_and_spki() {
        let server = test_server(false);
        // Route to a loopback IP while validating and sending SNI for localhost.
        let (result, accepted) = handshake(&server, trusted_connector(&server), "localhost").await;
        let der = result.unwrap();
        assert_eq!(accepted.unwrap().as_deref(), Some("localhost"));
        assert_eq!(der, server.leaf.as_ref());
        assert_eq!(extract_spki_from_cert_der(&der).unwrap(), server.spki);
    }

    #[tokio::test]
    async fn tls_rejects_an_untrusted_certificate() {
        let server = test_server(false);
        let (result, accepted) = handshake(
            &server,
            connector_with_roots(RootCertStore::empty()).unwrap(),
            "localhost",
        )
        .await;
        assert!(matches!(result, Err(Error::Tls(_))));
        assert!(accepted.is_err());
    }

    #[tokio::test]
    async fn tls_rejects_a_trusted_certificate_for_another_hostname() {
        let server = test_server(false);
        let (result, accepted) = handshake(&server, trusted_connector(&server), "other.test").await;
        assert!(matches!(result, Err(Error::Tls(_))));
        assert!(accepted.is_err());
    }

    #[tokio::test]
    async fn tls_rejects_an_expired_trusted_certificate() {
        let server = test_server(true);
        let (result, accepted) = handshake(&server, trusted_connector(&server), "localhost").await;
        assert!(matches!(result, Err(Error::Tls(_))));
        assert!(accepted.is_err());
    }

    #[tokio::test]
    async fn production_roots_reject_the_loopback_private_ca() {
        let server = test_server(false);
        let (result, accepted) = handshake(&server, webpki_connector().unwrap(), "localhost").await;
        assert!(matches!(result, Err(Error::Tls(_))));
        assert!(accepted.is_err());
    }

    #[tokio::test]
    async fn socks_tls_probe_rejects_untrusted_tls_without_a_direct_fallback() {
        let server = test_server(false);
        let direct_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let destination_port = direct_listener.local_addr().unwrap().port();
        let proxy_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let proxy_addr = proxy_listener.local_addr().unwrap();
        let acceptor = TlsAcceptor::from(server.config);
        let proxy = tokio::spawn(async move {
            let (mut stream, _) = proxy_listener.accept().await.unwrap();
            let mut greeting = [0; 2];
            stream.read_exact(&mut greeting).await.unwrap();
            assert_eq!(greeting[0], 5);
            let mut methods = vec![0; greeting[1] as usize];
            stream.read_exact(&mut methods).await.unwrap();
            assert!(methods.contains(&0));
            stream.write_all(&[5, 0]).await.unwrap();
            let mut request = [0; 4];
            stream.read_exact(&mut request).await.unwrap();
            assert_eq!(request, [5, 1, 0, 3], "SOCKS must receive a hostname");
            let mut hostname = vec![0; stream.read_u8().await.unwrap() as usize];
            stream.read_exact(&mut hostname).await.unwrap();
            assert_eq!(hostname, b"localhost");
            assert_eq!(stream.read_u16().await.unwrap(), destination_port);
            stream
                .write_all(&[5, 0, 0, 1, 127, 0, 0, 1, 0, 0])
                .await
                .unwrap();
            acceptor.accept(stream).await.is_err()
        });
        let manager = Arc::new(
            TransportManager::new(TransportConfig {
                mode: TransportMode::Socks5,
                socks5: Some(Socks5Config {
                    host: proxy_addr.ip().to_string(),
                    port: proxy_addr.port(),
                    username: None,
                    password: None,
                }),
                ..TransportConfig::default()
            })
            .await
            .unwrap(),
        );
        tokio::time::timeout(TEST_TIMEOUT, async {
            // The route hostname is forwarded to SOCKS; the independently
            // supplied TLS hostname must still be validated by the connector.
            let result = manager
                .fetch_spki_pin(
                    "localhost".to_owned(),
                    destination_port,
                    "localhost".to_owned(),
                )
                .await;
            assert!(matches!(result, Err(Error::Tls(_))));
            assert!(proxy.await.unwrap(), "untrusted TLS must be rejected");
        })
        .await
        .expect("SOCKS TLS test timed out");
        assert!(
            tokio::time::timeout(Duration::from_millis(50), direct_listener.accept())
                .await
                .is_err(),
            "a TLS failure must not open a direct connection"
        );
    }
}
