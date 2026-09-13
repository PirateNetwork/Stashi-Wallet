import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/features/settings/providers/preferences_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const native = MethodChannel('com.pirate.wallet/keystore');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('late saved appearance cannot undo the user selection', () async {
    final read = Completer<String?>();
    final writes = <String>[];
    Future<Object?> handler(MethodCall call) async {
      if (call.method == 'read' || call.method == 'readPreference') {
        return read.future;
      }
      writes.add((call.arguments as Map)['value'] as String);
      return null;
    }

    messenger.setMockMethodCallHandler(secure, handler);
    messenger.setMockMethodCallHandler(native, handler);
    final container = ProviderContainer();
    addTearDown(() {
      container.dispose();
      messenger.setMockMethodCallHandler(secure, null);
      messenger.setMockMethodCallHandler(native, null);
    });
    container.read(appThemeModeProvider);
    final notifier = container.read(appThemeModeProvider.notifier);
    final dark = notifier.setThemeMode(AppThemeMode.dark);
    final light = notifier.setThemeMode(AppThemeMode.light);
    await Future.wait([dark, light]);
    read.complete('dark');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(appThemeModeProvider), AppThemeMode.light);
    expect(writes, ['dark', 'light']);
  });
}
