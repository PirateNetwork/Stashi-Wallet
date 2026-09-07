import 'dart:async';

import '../../support/theme_test_fixtures.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/features/settings/providers/theme_preferences.dart';

class _Store extends ThemePreferenceStore {
  String? value;
  Completer<String?>? pendingRead;
  bool fail = false;
  final writes = <String>[];
  @override
  Future<String?> read() async =>
      pendingRead == null ? value : pendingRead!.future;
  @override
  Future<void> write(String id) async {
    if (fail) throw StateError('unavailable storage');
    writes.add(id);
    value = id;
  }
}

void main() {
  late _Store store;
  late ProviderContainer container;
  setUp(() {
    store = _Store();
    container = ProviderContainer(
      overrides: [
        themePreferenceStoreProvider.overrideWithValue(store),
        walletThemesProvider.overrideWithValue(testWalletThemes),
      ],
    );
  });
  tearDown(() => container.dispose());

  test('new installation keeps default; saved selection restores', () async {
    expect(container.read(walletThemeProvider).id, 'default');
    await container.read(walletThemeProvider.notifier).select('test-teal');
    expect(store.value, 'test-teal');
    container.invalidate(walletThemeProvider);
    container.read(walletThemeProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(walletThemeProvider).id, 'test-teal');
  });

  test('unknown saved theme falls back without changing storage', () async {
    store.value = 'removed-theme';
    container.read(walletThemeProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(walletThemeProvider).id, 'default');
    expect(store.value, 'removed-theme');
  });

  test('late storage read cannot overwrite a user selection', () async {
    store.pendingRead = Completer<String?>();
    container.read(walletThemeProvider);
    await Future<void>.delayed(Duration.zero);
    await container.read(walletThemeProvider.notifier).select('test-teal');
    store.pendingRead!.complete('default');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(walletThemeProvider).id, 'test-teal');
  });

  test('rapid changes persist in selection order', () async {
    final notifier = container.read(walletThemeProvider.notifier);
    await Future.wait([
      notifier.select('test-teal'),
      notifier.select('default'),
    ]);
    expect(store.writes, ['test-teal', 'default']);
    expect(store.value, 'default');
    expect(container.read(walletThemeProvider).id, 'default');
  });

  test('failed write restores the previous selection', () async {
    final notifier = container.read(walletThemeProvider.notifier);
    store.fail = true;
    await expectLater(notifier.select('test-teal'), throwsStateError);
    expect(container.read(walletThemeProvider).id, 'default');
  });

  test('failed queued writes restore the last persisted theme', () async {
    final notifier = container.read(walletThemeProvider.notifier);
    await notifier.select('test-teal');
    store.fail = true;
    await Future.wait([
      expectLater(notifier.select('default'), throwsStateError),
      expectLater(notifier.select('test-teal'), throwsStateError),
    ]);
    expect(container.read(walletThemeProvider).id, 'test-teal');
    expect(store.value, 'test-teal');
  });
}
