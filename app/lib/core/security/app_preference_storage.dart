import 'dart:io';

import 'package:flutter/services.dart';

import 'app_secure_storage.dart';

/// Non-secret preferences only. macOS migrates accessible legacy values without
/// displaying Keychain authorization UI, then persists them in UserDefaults.
/// Secrets and proxy credentials must continue to use appSecureStorage.
class AppPreferenceStorage {
  const AppPreferenceStorage({this.isMacOS});

  final bool? isMacOS;
  static const _channel = MethodChannel('com.pirate.wallet/keystore');

  Future<String?> read({required String key}) async {
    if (!(isMacOS ?? Platform.isMacOS)) return appSecureStorage.read(key: key);
    return _channel.invokeMethod<String>('readPreference', {'key': key});
  }

  Future<void> write({required String key, required String value}) async {
    if (!(isMacOS ?? Platform.isMacOS)) {
      return appSecureStorage.write(key: key, value: value);
    }
    await _channel.invokeMethod<void>('writePreference', {
      'key': key,
      'value': value,
    });
  }
}

const appPreferenceStorage = AppPreferenceStorage();
