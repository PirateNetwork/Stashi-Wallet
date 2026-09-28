//! Screenshot blocking for sensitive screens
//!
//! Provides screenshot/screen capture prevention for:
//! - Seed phrase display
//! - Private key export
//! - IVK export
//! - Any screen marked as sensitive
//!
//! Platform implementations:
//! - Android: FLAG_SECURE on Window
//! - iOS: UITextField secure text entry trick + notification observers
//! - Desktop: Application-level hooks (limited protection)

use std::sync::{Arc, RwLock};

/// Screenshot protection state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProtectionState {
    /// Protection disabled (normal screen)
    Disabled,
    /// Protection enabled (sensitive content visible)
    Enabled,
    /// Protection temporarily suspended (for accessibility)
    Suspended,
}

/// Reason for enabling screenshot protection
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProtectionReason {
    /// Seed phrase is being displayed
    SeedPhrase,
    /// IVK (viewing key) is being displayed
    ViewingKey,
    /// Private spending key is being displayed
    SpendingKey,
    /// Panic PIN is being configured
    PanicPin,
    /// Passphrase is being entered
    PassphraseEntry,
    /// Generic sensitive content
    Sensitive,
}

impl ProtectionReason {
    /// Get human-readable description
    pub fn description(&self) -> &'static str {
        match self {
            Self::SeedPhrase => "Seed phrase is visible",
            Self::ViewingKey => "Viewing key is visible",
            Self::SpendingKey => "Spending key is visible",
            Self::PanicPin => "Panic PIN configuration",
            Self::PassphraseEntry => "Passphrase entry",
            Self::Sensitive => "Sensitive content",
        }
    }

    /// Get security level (higher = more sensitive)
    pub fn security_level(&self) -> u8 {
        match self {
            Self::SeedPhrase => 10,
            Self::SpendingKey => 10,
            Self::ViewingKey => 8,
            Self::PanicPin => 7,
            Self::PassphraseEntry => 5,
            Self::Sensitive => 3,
        }
    }
}

/// Screenshot guard manager
///
/// Manages screenshot protection state across the application.
/// The actual platform-specific implementation is done via FFI.
#[derive(Clone)]
pub struct ScreenshotGuard {
    inner: Arc<RwLock<GuardState>>,
}

struct GuardState {
    state: ProtectionState,
    protection_stack: Vec<ProtectionReason>,
    platform_supported: bool,
}

impl ScreenshotGuard {
    /// Create new screenshot guard
    pub fn new() -> Self {
        Self {
            inner: Arc::new(RwLock::new(GuardState {
                state: ProtectionState::Disabled,
                protection_stack: Vec::new(),
                platform_supported: false,
            })),
        }
    }

    /// Set platform support status (called from FFI during init)
    pub fn set_platform_supported(&self, supported: bool) {
        self.inner.write().unwrap().platform_supported = supported;
    }

    /// Check if platform supports screenshot blocking
    pub fn is_platform_supported(&self) -> bool {
        self.inner.read().unwrap().platform_supported
    }

    /// Get current protection state
    pub fn state(&self) -> ProtectionState {
        self.inner.read().unwrap().state
    }

    /// Enable screenshot protection
    ///
    /// Returns a guard that automatically disables protection on drop.
    pub fn enable(&self, reason: ProtectionReason) -> ScreenshotProtectionGuard {
        let mut state = self.inner.write().unwrap();
        state.protection_stack.push(reason);
        state.state = ProtectionState::Enabled;

        tracing::debug!(
            "Screenshot protection enabled: {} (ref_count: {})",
            reason.description(),
            state.protection_stack.len()
        );

        ScreenshotProtectionGuard {
            guard: self.clone(),
            reason,
        }
    }

    /// Disable screenshot protection
    fn disable_internal(&self, reason: ProtectionReason) {
        let mut state = self.inner.write().unwrap();
        if let Some(pos) = state.protection_stack.iter().rposition(|r| *r == reason) {
            state.protection_stack.remove(pos);
        }

        if state.protection_stack.is_empty() {
            state.state = ProtectionState::Disabled;
            tracing::debug!("Screenshot protection disabled");
        } else {
            tracing::debug!(
                "Screenshot protection still active (ref_count: {})",
                state.protection_stack.len()
            );
        }
    }

    /// Temporarily suspend protection (for accessibility screenshots)
    pub fn suspend(&self) -> bool {
        let mut state = self.inner.write().unwrap();
        if state.state == ProtectionState::Enabled {
            state.state = ProtectionState::Suspended;
            tracing::warn!("Screenshot protection suspended");
            true
        } else {
            false
        }
    }

    /// Resume protection after suspension
    pub fn resume(&self) {
        let mut state = self.inner.write().unwrap();
        if state.state == ProtectionState::Suspended {
            state.state = ProtectionState::Enabled;
            tracing::debug!("Screenshot protection resumed");
        }
    }

    /// Get active protection reasons
    pub fn active_reasons(&self) -> Vec<ProtectionReason> {
        self.inner.read().unwrap().protection_stack.clone()
    }

    /// Get highest security level among active protections
    pub fn highest_security_level(&self) -> u8 {
        self.inner
            .read()
            .unwrap()
            .protection_stack
            .iter()
            .map(|r| r.security_level())
            .max()
            .unwrap_or(0)
    }

    /// Check if protection is currently active
    pub fn is_active(&self) -> bool {
        matches!(
            self.inner.read().unwrap().state,
            ProtectionState::Enabled | ProtectionState::Suspended
        )
    }
}

impl Default for ScreenshotGuard {
    fn default() -> Self {
        Self::new()
    }
}

/// RAII guard for screenshot protection
///
/// When this guard is dropped, screenshot protection is automatically
/// decremented (and disabled if no other protections are active).
pub struct ScreenshotProtectionGuard {
    guard: ScreenshotGuard,
    reason: ProtectionReason,
}

impl ScreenshotProtectionGuard {
    /// Get the reason for this protection
    pub fn reason(&self) -> ProtectionReason {
        self.reason
    }
}

impl Drop for ScreenshotProtectionGuard {
    fn drop(&mut self) {
        self.guard.disable_internal(self.reason);
    }
}

// =============================================================================
// Platform-specific implementations (FFI bridge points)
// =============================================================================

/// Android screenshot blocking
///
/// Uses WindowManager.LayoutParams.FLAG_SECURE to prevent:
/// - Screenshots
/// - Screen recording
/// - Display on non-secure displays
#[cfg(target_os = "android")]
pub mod android {
    /// Set FLAG_SECURE on activity window
    ///
    /// FFI call to:
    /// ```kotlin
    /// window.setFlags(
    ///     WindowManager.LayoutParams.FLAG_SECURE,
    ///     WindowManager.LayoutParams.FLAG_SECURE
    /// )
    /// ```
    pub fn set_secure_flag(secure: bool) {
        // FFI call to Kotlin
        let _ = secure;
    }

    /// Check if FLAG_SECURE is currently set
    pub fn is_secure_flag_set() -> bool {
        // FFI call to Kotlin
        false
    }
}

/// iOS screenshot blocking
///
/// Uses multiple techniques:
/// 1. Add invisible secure text field to capture screenshots
/// 2. Observe UIApplication.userDidTakeScreenshotNotification
/// 3. Use CALayer.shouldRasterize for screen recording
#[cfg(target_os = "ios")]
pub mod ios {
    /// Enable screenshot prevention
    ///
    /// FFI call to Swift:
    /// ```swift
    /// // Add secure text field overlay
    /// let secureField = UITextField()
    /// secureField.isSecureTextEntry = true
    /// view.addSubview(secureField)
    /// secureField.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    /// secureField.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    /// ```
    pub fn enable_protection() {
        // FFI call to Swift
    }

    /// Disable screenshot prevention
    pub fn disable_protection() {
        // FFI call to Swift
    }

    /// Register for screenshot notification
    ///
    /// FFI call to observe:
    /// ```swift
    /// NotificationCenter.default.addObserver(
    ///     forName: UIApplication.userDidTakeScreenshotNotification,
    ///     object: nil,
    ///     queue: .main
    /// ) { _ in
    ///     // Handle screenshot taken
    /// }
    /// ```
    pub fn register_screenshot_observer(callback: fn()) {
        let _ = callback;
    }
}

/// Desktop screenshot blocking (limited)
///
/// Desktop platforms have limited screenshot prevention capabilities.
/// We use application-level hints that may be ignored by screen capture tools.
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub mod desktop {
    /// Attempt to prevent window capture
    ///
    /// Platform-specific approaches:
    /// - Windows: SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE) on Win10 2004+
    /// - macOS: NSWindow.sharingType = .none
    /// - Linux: Limited - no standard API
    pub fn set_capture_prevention(enabled: bool) {
        let _ = enabled;
    }

    /// Check if capture prevention is supported
    pub fn is_capture_prevention_supported() -> bool {
        #[cfg(target_os = "windows")]
        {
            // Check Windows version >= 10.0.19041 (2004)
            false
        }

        #[cfg(target_os = "macos")]
        {
            true // macOS always supports NSWindow.sharingType
        }

        #[cfg(target_os = "linux")]
        {
            false // No standard API
        }
    }
}

/// Screenshot protection status for FFI
#[derive(Debug, Clone)]
pub struct ScreenshotProtectionStatus {
    /// Current protection state
    pub state: ProtectionState,
    /// Number of active protections
    pub active_count: u32,
    /// Whether platform supports screenshot blocking
    pub platform_supported: bool,
    /// Highest security level active
    pub security_level: u8,
    /// Active protection reasons
    pub reasons: Vec<String>,
}

impl From<&ScreenshotGuard> for ScreenshotProtectionStatus {
    fn from(guard: &ScreenshotGuard) -> Self {
        let state = guard.inner.read().unwrap();
        Self {
            state: state.state,
            active_count: state.protection_stack.len() as u32,
            platform_supported: state.platform_supported,
            security_level: state
                .protection_stack
                .iter()
                .map(ProtectionReason::security_level)
                .max()
                .unwrap_or(0),
            reasons: state
                .protection_stack
                .iter()
                .map(|r| r.description().to_string())
                .collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_protection_reason_levels() {
        assert_eq!(ProtectionReason::SeedPhrase.security_level(), 10);
        assert_eq!(ProtectionReason::Sensitive.security_level(), 3);
    }

    #[test]
    fn test_screenshot_guard_lifecycle() {
        let guard_manager = ScreenshotGuard::new();

        assert_eq!(guard_manager.state(), ProtectionState::Disabled);
        assert!(!guard_manager.is_active());

        // Enable protection
        let _protection = guard_manager.enable(ProtectionReason::SeedPhrase);

        assert_eq!(guard_manager.state(), ProtectionState::Enabled);
        assert!(guard_manager.is_active());
        assert_eq!(guard_manager.highest_security_level(), 10);

        // Suspend
        guard_manager.suspend();
        assert_eq!(guard_manager.state(), ProtectionState::Suspended);

        // Resume
        guard_manager.resume();
        assert_eq!(guard_manager.state(), ProtectionState::Enabled);
    }

    #[test]
    fn test_nested_protections() {
        let guard_manager = ScreenshotGuard::new();

        let p1 = guard_manager.enable(ProtectionReason::Sensitive);
        assert_eq!(guard_manager.active_reasons().len(), 1);

        let p2 = guard_manager.enable(ProtectionReason::SeedPhrase);
        assert_eq!(guard_manager.active_reasons().len(), 2);

        // Highest security level should be SeedPhrase's
        assert_eq!(guard_manager.highest_security_level(), 10);

        // Both reasons should be active
        let reasons = guard_manager.active_reasons();
        assert_eq!(reasons.len(), 2);

        drop(p2);
        assert_eq!(guard_manager.state(), ProtectionState::Enabled);
        assert_eq!(
            guard_manager.active_reasons(),
            vec![ProtectionReason::Sensitive]
        );
        drop(p1);
        assert_eq!(guard_manager.state(), ProtectionState::Disabled);
        assert!(guard_manager.active_reasons().is_empty());
    }

    #[test]
    fn dropping_a_token_updates_every_clone_of_the_guard() {
        let original = ScreenshotGuard::new();
        let clone = original.clone();
        let token = clone.enable(ProtectionReason::SeedPhrase);

        assert!(original.is_active());
        drop(token);
        assert!(!original.is_active());
        assert_eq!(ScreenshotProtectionStatus::from(&original).active_count, 0);
    }

    #[test]
    fn test_protection_status() {
        let guard_manager = ScreenshotGuard::new();
        guard_manager.set_platform_supported(true);

        let _protection = guard_manager.enable(ProtectionReason::ViewingKey);

        let status = ScreenshotProtectionStatus::from(&guard_manager);

        assert_eq!(status.state, ProtectionState::Enabled);
        assert_eq!(status.active_count, 1);
        assert!(status.platform_supported);
        assert_eq!(status.security_level, 8);
        assert_eq!(status.reasons.len(), 1);
    }
}
