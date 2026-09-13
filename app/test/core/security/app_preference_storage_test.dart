import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/security/app_preference_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('com.pirate.wallet/keystore');
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final binding =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    binding.setMockMethodCallHandler(native, null);
    binding.setMockMethodCallHandler(secure, null);
  });

  test(
    'macOS preferences never use the interactive secure storage plugin',
    () async {
      final values = <String, String>{'ui_theme_mode_v1': 'light'};
      binding.setMockMethodCallHandler(
        secure,
        (_) async => throw StateError('Unexpected Keychain request'),
      );
      binding.setMockMethodCallHandler(native, (call) async {
        final args = call.arguments as Map;
        if (call.method == 'readPreference') return values[args['key']];
        expect(call.method, 'writePreference');
        values[args['key'] as String] = args['value'] as String;
        return null;
      });
      const store = AppPreferenceStorage(isMacOS: true);
      expect(await store.read(key: 'ui_theme_mode_v1'), 'light');
      await store.write(key: 'ui_theme_mode_v1', value: 'dark');
      expect(await store.read(key: 'ui_theme_mode_v1'), 'dark');
    },
  );

  test('native preference failures propagate instead of requesting Keychain access', () async {
    binding.setMockMethodCallHandler(
      native,
      (_) async => throw PlatformException(code: 'INVALID_PREFERENCE'),
    );
    const store = AppPreferenceStorage(isMacOS: true);
    await expectLater(
      store.read(key: 'transport_config_v1'),
      throwsA(isA<PlatformException>()),
    );
  });
}
