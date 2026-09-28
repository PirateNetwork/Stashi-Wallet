// Screenshot and screen recording protection
//
// Prevents screenshots when viewing sensitive data like seed phrases

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Screenshot protection manager
class ScreenshotProtection {
  static const MethodChannel _channel = MethodChannel(
    'com.pirate.wallet/security',
  );

  static bool _isProtected = false;
  static int _activeScopes = 0;
  static Future<void> _pending = Future<void>.value();

  /// Hold screenshot protection until the matching disable call.
  static Future<void> enable() async {
    _activeScopes++;
    await _reconcile();
  }

  /// Release one protection scope.
  static Future<void> disable() async {
    if (_activeScopes == 0) {
      await _pending;
      return;
    }
    _activeScopes--;
    await _reconcile();
  }

  static Future<void> _reconcile() {
    // Platform calls are asynchronous. Serialize them and read the latest scope
    // count when each call runs so a late enable cannot undo a later disable.
    _pending = _pending.then((_) => _applyDesiredState());
    return _pending;
  }

  static Future<void> _applyDesiredState() async {
    final shouldProtect = _activeScopes > 0;
    if (shouldProtect == _isProtected) return;
    try {
      if (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux) {
        if (shouldProtect) {
          final enabled = await _channel.invokeMethod(
            'enableScreenshotProtection',
          );
          _isProtected = enabled == true;
        } else {
          await _channel.invokeMethod('disableScreenshotProtection');
          _isProtected = false;
        }
      }
    } on PlatformException catch (e) {
      debugPrint('Screenshot protection failed: ${e.message}');
    } on MissingPluginException catch (_) {
      // Platform channel not implemented on this platform
    }
  }

  /// Check if currently protected
  static bool get isProtected => _isProtected;

  /// Protect a screen temporarily (auto-disable on dispose)
  static ScreenProtection protect() {
    return ScreenProtection._();
  }
}

/// Screen protection lifecycle manager
class ScreenProtection {
  bool _disposed = false;

  ScreenProtection._() {
    ScreenshotProtection.enable();
  }

  /// Dispose and remove protection
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ScreenshotProtection.disable();
  }
}

/// Widget mixin for automatic screenshot protection
mixin ScreenshotProtectionMixin {
  ScreenProtection? _protection;

  /// Enable protection for this screen
  void enableScreenshotProtection() {
    _protection ??= ScreenshotProtection.protect();
  }

  /// Disable protection
  void disableScreenshotProtection() {
    _protection?.dispose();
    _protection = null;
  }

  /// Call in dispose
  void disposeScreenshotProtection() {
    _protection?.dispose();
    _protection = null;
  }
}
