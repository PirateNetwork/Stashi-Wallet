import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/security/screenshot_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'capture override is opt-in and leaves protection state accurate',
    () async {
      // Exercise both build configurations by running with/without the define.
      // ignore: do_not_use_environment
      const allowCapture = bool.fromEnvironment('STASHI_ALLOW_SCREEN_CAPTURE');
      const channel = MethodChannel('com.pirate.wallet/security');
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await ScreenshotProtection.enable();
      expect(ScreenshotProtection.isProtected, !allowCapture);
      await ScreenshotProtection.disable();
      expect(ScreenshotProtection.isProtected, isFalse);
      expect(
        calls,
        allowCapture
            ? isEmpty
            : ['enableScreenshotProtection', 'disableScreenshotProtection'],
      );
    },
  );
}
