import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pirate_wallet/core/providers/wallet_providers.dart';
import 'package:pirate_wallet/design/theme.dart';
import 'package:pirate_wallet/features/keys/import_spending_key_screen.dart';
import 'package:pirate_wallet/ui/atoms/p_input.dart';

class _ActiveWallet extends ActiveWalletNotifier {
  @override
  String? build() => 'import-wallet';

  void changeForTest() => state = 'another-wallet';
}

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(PInput, label),
  matching: find.byType(TextField),
);

class _ImportHarness {
  int imports = 0;
  int scans = 0;
  String? sapling;
  String? ironwood;
  String? scannedWallet;
  int? scannedHeight;
  bool failScan = false;
  Error? importError;
  Completer<int>? pendingImport;
  late ProviderContainer container;
  late GoRouter router;

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    container = ProviderContainer(
      overrides: [
        activeWalletProvider.overrideWith(_ActiveWallet.new),
        refreshWalletRuntimeProvider.overrideWithValue(() {}),
        spendingKeyImporterProvider.overrideWithValue(({
          required String walletId,
          String? saplingKey,
          String? ironwoodKey,
          String? label,
          required int birthdayHeight,
        }) async {
          imports++;
          sapling = saplingKey;
          ironwood = ironwoodKey;
          if (importError != null) throw importError!;
          return pendingImport == null ? 42 : await pendingImport!.future;
        }),
        importedKeyRescanProvider.overrideWithValue((
          String walletId,
          int height,
        ) async {
          scans++;
          scannedWallet = walletId;
          scannedHeight = height;
          if (failScan) throw StateError('scan unavailable');
        }),
      ],
    );
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Wallet')),
        ),
        GoRoute(
          path: '/import',
          builder: (_, _) => const ImportSpendingKeyScreen(),
        ),
        GoRoute(
          path: '/settings/keys/detail',
          builder: (_, state) => Scaffold(
            body: Text('Imported key ${state.uri.queryParameters['keyId']}'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: PTheme.dark(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    unawaited(router.push('/import'));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      container.dispose();
    });
  }

  Future<void> enter(
    WidgetTester tester,
    String key, {
    String height = '100',
  }) async {
    await tester.enterText(_field('Spending key'), key);
    await tester.enterText(_field('Birthday height'), height);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Import and scan'));
    await tester.tap(find.text('Import and scan'));
    await tester.pump();
  }
}

void main() {
  for (final key in [
    'secret-extended-key-main1qqqq',
    'pirate-secret-extended-key1qqqq',
  ]) {
    testWidgets('imports detected format $key and opens its details', (
      tester,
    ) async {
      final harness = _ImportHarness();
      await harness.pump(tester);
      await harness.enter(tester, key);
      await harness.submit(tester);
      await tester.pumpAndSettle();
      expect(harness.imports, 1);
      expect(harness.sapling, key.startsWith('pirate-') ? isNull : key);
      expect(harness.ironwood, key.startsWith('pirate-') ? key : isNull);
      expect(harness.scannedWallet, 'import-wallet');
      expect(harness.scannedHeight, 100);
      expect(find.text('Imported key 42'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('validates both fields before touching the native importer', (
    tester,
  ) async {
    final harness = _ImportHarness();
    await harness.pump(tester);
    await harness.enter(tester, 'zs1notaspendingkey', height: '4294967296');
    await harness.submit(tester);
    await tester.pumpAndSettle();
    expect(harness.imports, 0);
    expect(find.text('Enter a valid birthday height'), findsOneWidget);
    expect(
      find.textContaining('not an address or viewing key'),
      findsOneWidget,
    );
  });

  testWidgets('scan retry never reimports an already stored key', (
    tester,
  ) async {
    final harness = _ImportHarness()..failScan = true;
    await harness.pump(tester);
    await harness.enter(
      tester,
      'secret-extended-key-main1qqqq pirate-secret-extended-key1qqqq',
    );
    await harness.submit(tester);
    await tester.pumpAndSettle();
    expect(harness.imports, 1);
    expect(harness.sapling, isNotNull);
    expect(harness.ironwood, isNotNull);
    expect(
      tester.widget<TextField>(_field('Spending key')).controller!.text,
      isEmpty,
    );
    expect(find.textContaining('Your key is imported.'), findsOneWidget);
    harness.failScan = false;
    await tester.ensureVisible(find.text('Retry scanning'));
    await tester.tap(find.text('Retry scanning'));
    await tester.pumpAndSettle();
    expect(harness.imports, 1);
    expect(harness.scans, 2);
    expect(find.text('Imported key 42'), findsOneWidget);
  });

  testWidgets('keeps keyboard learning off after revealing the key', (
    tester,
  ) async {
    final harness = _ImportHarness();
    await harness.pump(tester);
    expect(
      tester.widget<TextField>(_field('Spending key')).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Show key'));
    await tester.pump();
    final field = tester.widget<TextField>(_field('Spending key'));
    expect(field.obscureText, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(field.autocorrect, isFalse);
  });

  testWidgets('never renders private material from an import exception', (
    tester,
  ) async {
    final harness = _ImportHarness()
      ..importError = StateError('secret-native-diagnostics');
    await harness.pump(tester);
    await harness.enter(tester, 'secret-extended-key-main1qqqq');
    await harness.submit(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('secret-native-diagnostics'), findsNothing);
    expect(find.textContaining('Could not import the key.'), findsOneWidget);
    expect(harness.scans, 0);
  });

  testWidgets('finishes safely when the route is removed during import', (
    tester,
  ) async {
    final harness = _ImportHarness()..pendingImport = Completer<int>();
    await harness.pump(tester);
    await harness.enter(tester, 'secret-extended-key-main1qqqq');
    await harness.submit(tester);
    harness.router.go('/');
    await tester.pumpAndSettle();
    harness.pendingImport!.completeError(StateError('import cancelled'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(harness.scans, 0);
  });

  testWidgets(
    'uses the original wallet if active selection changes mid-import',
    (tester) async {
      final harness = _ImportHarness()..pendingImport = Completer<int>();
      await harness.pump(tester);
      await harness.enter(tester, 'secret-extended-key-main1qqqq');
      await harness.submit(tester);
      (harness.container.read(activeWalletProvider.notifier) as _ActiveWallet)
          .changeForTest();
      harness.pendingImport!.complete(42);
      await tester.pumpAndSettle();
      expect(harness.scannedWallet, 'import-wallet');
      expect(find.text('Imported key 42'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fits narrow screens with enlarged text and keeps the action reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = _ImportHarness();
      await harness.pump(tester, textScale: 1.6);
      await tester.ensureVisible(find.text('Import and scan'));
      await tester.pumpAndSettle();
      expect(find.text('Import and scan').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
