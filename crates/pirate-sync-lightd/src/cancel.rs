//! Cancellation primitive for long-running sync tasks.

use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use tokio::sync::Notify;

/// Cancellation token that can be cloned and shared across tasks.
///
/// This is intentionally lightweight and does not require locking the `SyncEngine`.
#[derive(Clone)]
pub struct CancelToken {
    cancelled: Arc<AtomicBool>,
    notify: Arc<Notify>,
}

impl CancelToken {
    /// Create a new token in the non-cancelled state.
    pub fn new() -> Self {
        Self {
            cancelled: Arc::new(AtomicBool::new(false)),
            notify: Arc::new(Notify::new()),
        }
    }

    /// Returns `true` if cancellation has been requested.
    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }

    /// Request cancellation and wake any waiters.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        self.notify.notify_waiters();
    }

    /// Reset the token to the non-cancelled state.
    ///
    /// Only call this when no tasks from the previous run are still using this token.
    pub fn reset(&self) {
        self.cancelled.store(false, Ordering::Release);
    }

    /// Await until cancellation is requested.
    pub async fn cancelled(&self) {
        // Register before checking the flag: notify_waiters does not retain a
        // permit, so cancellation between the check and registration could
        // otherwise leave a transport handoff waiting indefinitely.
        let notified = self.notify.notified();
        tokio::pin!(notified);
        notified.as_mut().enable();
        if self.is_cancelled() {
            return;
        }
        notified.await;
    }
}

impl Default for CancelToken {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn cancellation_wakes_all_registered_waiters_and_late_waiters() {
        let token = CancelToken::new();
        let first = token.cancelled();
        let second = token.cancelled();
        tokio::pin!(first, second);
        assert!(futures_util::poll!(&mut first).is_pending());
        assert!(futures_util::poll!(&mut second).is_pending());
        token.cancel();
        tokio::time::timeout(Duration::from_secs(1), async {
            first.await;
            second.await;
            token.cancelled().await;
        })
        .await
        .expect("cancellation must not lose wakeups");
    }
}
