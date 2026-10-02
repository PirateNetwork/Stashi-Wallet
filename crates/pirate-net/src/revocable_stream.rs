//! Retire established transport connections, not only future connection attempts.

use std::future::Future;
use std::io;
use std::pin::Pin;
use std::task::{Context, Poll};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio_util::sync::{CancellationToken, WaitForCancellationFutureOwned};

pub(crate) struct RevocableStream<T> {
    inner: Option<T>,
    read_revoked: Pin<Box<WaitForCancellationFutureOwned>>,
    write_revoked: Pin<Box<WaitForCancellationFutureOwned>>,
}

impl<T> RevocableStream<T> {
    pub(crate) fn new(inner: T, token: CancellationToken) -> Self {
        Self {
            inner: Some(inner),
            read_revoked: Box::pin(token.clone().cancelled_owned()),
            write_revoked: Box::pin(token.cancelled_owned()),
        }
    }

    fn check(&mut self, cx: &mut Context<'_>, reading: bool) -> io::Result<()> {
        let revoked = if reading {
            &mut self.read_revoked
        } else {
            &mut self.write_revoked
        };
        if revoked.as_mut().poll(cx).is_ready() {
            // Drop the socket as well as refusing subsequent reads and writes.
            self.inner = None;
            Err(io::Error::new(
                io::ErrorKind::ConnectionAborted,
                "Transport selection changed; connection retired",
            ))
        } else {
            Ok(())
        }
    }
}

impl<T: AsyncRead + Unpin> AsyncRead for RevocableStream<T> {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        if let Err(error) = this.check(cx, true) {
            return Poll::Ready(Err(error));
        }
        Pin::new(this.inner.as_mut().expect("live stream")).poll_read(cx, buf)
    }
}

impl<T: AsyncWrite + Unpin> AsyncWrite for RevocableStream<T> {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        let this = self.get_mut();
        if let Err(error) = this.check(cx, false) {
            return Poll::Ready(Err(error));
        }
        Pin::new(this.inner.as_mut().expect("live stream")).poll_write(cx, buf)
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        if let Err(error) = this.check(cx, false) {
            return Poll::Ready(Err(error));
        }
        Pin::new(this.inner.as_mut().expect("live stream")).poll_flush(cx)
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        if let Err(error) = this.check(cx, false) {
            return Poll::Ready(Err(error));
        }
        Pin::new(this.inner.as_mut().expect("live stream")).poll_shutdown(cx)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    #[tokio::test]
    async fn retirement_wakes_pending_reads_and_closes_the_socket() {
        let (socket, mut peer) = tokio::io::duplex(32);
        let token = CancellationToken::new();
        let mut stream = RevocableStream::new(socket, token.clone());
        let read = tokio::spawn(async move { stream.read_u8().await });
        tokio::task::yield_now().await;
        token.cancel();
        let error = tokio::time::timeout(std::time::Duration::from_secs(1), read)
            .await
            .expect("revocation must wake a pending read")
            .unwrap()
            .unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::ConnectionAborted);
        assert_eq!(peer.read(&mut [0]).await.unwrap(), 0);
    }

    #[tokio::test]
    async fn retirement_prevents_old_channels_from_writing_again() {
        let (socket, mut peer) = tokio::io::duplex(32);
        let token = CancellationToken::new();
        let mut stream = RevocableStream::new(socket, token.clone());
        stream.write_all(b"before").await.unwrap();
        let mut received = [0; 6];
        peer.read_exact(&mut received).await.unwrap();
        assert_eq!(&received, b"before");
        token.cancel();
        assert_eq!(
            stream.write_all(b"after").await.unwrap_err().kind(),
            io::ErrorKind::ConnectionAborted
        );
        assert_eq!(peer.read(&mut [0]).await.unwrap(), 0);
    }

    #[tokio::test]
    async fn retirement_wakes_both_split_io_halves() {
        let (mut socket, _peer) = tokio::io::duplex(1);
        socket.write_all(b"x").await.unwrap();
        let token = CancellationToken::new();
        let (mut read, mut write) = tokio::io::split(RevocableStream::new(socket, token.clone()));
        let reader = tokio::spawn(async move { read.read_u8().await });
        let writer = tokio::spawn(async move { write.write_all(b"y").await });
        tokio::task::yield_now().await;
        token.cancel();
        tokio::time::timeout(std::time::Duration::from_secs(1), async {
            assert_eq!(
                reader.await.unwrap().unwrap_err().kind(),
                io::ErrorKind::ConnectionAborted
            );
            assert_eq!(
                writer.await.unwrap().unwrap_err().kind(),
                io::ErrorKind::ConnectionAborted
            );
        })
        .await
        .expect("both cancellation waiters must be woken");
    }
}
