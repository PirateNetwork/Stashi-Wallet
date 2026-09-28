import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/security/screenshot_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.pirate.wallet/security');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('nested sensitive screens keep capture blocked', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'enableScreenshotProtection';
    });

    final first = ScreenshotProtection.protect();
    final second = ScreenshotProtection.protect();
    await Future<void>.delayed(Duration.zero);
    expect(ScreenshotProtection.isProtected, isTrue);
    expect(calls, ['enableScreenshotProtection']);

    first.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(ScreenshotProtection.isProtected, isTrue);
    expect(calls, ['enableScreenshotProtection']);

    second.dispose();
    second.dispose();
    await ScreenshotProtection.disable();
    expect(ScreenshotProtection.isProtected, isFalse);
    expect(calls, [
      'enableScreenshotProtection',
      'disableScreenshotProtection',
    ]);
  });

  test('a late enable cannot leave capture enabled after dispose', () async {
    final enableStarted = Completer<void>();
    final allowEnable = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'enableScreenshotProtection') {
        enableStarted.complete();
        await allowEnable.future;
        return true;
      }
      return null;
    });

    final protection = ScreenshotProtection.protect();
    await enableStarted.future;
    protection.dispose();
    allowEnable.complete();
    await ScreenshotProtection.disable();

    expect(ScreenshotProtection.isProtected, isFalse);
    expect(calls, [
      'enableScreenshotProtection',
      'disableScreenshotProtection',
    ]);
  });
}
