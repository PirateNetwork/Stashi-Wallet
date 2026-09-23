import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pirate_wallet/core/ffi/generated/frb_generated.dart';
import 'package:pirate_wallet/core/ffi/generated/models.dart';
import 'package:pirate_wallet/core/providers/wallet_providers.dart';
import 'package:pirate_wallet/design/theme.dart';
import 'package:pirate_wallet/design/tokens/colors.dart';
import 'package:pirate_wallet/features/keys/key_detail_screen.dart';
import 'package:pirate_wallet/features/settings/providers/preferences_providers.dart';
import 'package:pirate_wallet/ui/atoms/p_button.dart';
import 'package:pirate_wallet/ui/organisms/p_scaffold.dart';

import '../../support/restored_wallet_api.dart';

const _captureKey = ValueKey('imported-key-removal-capture');

class _Wallet extends ActiveWalletNotifier {
  @override
  String? build() => 'removal-test-wallet';
}

class _Mode extends DecoyModeNotifier {
  @override
  bool build() => false;
}

class _BiometricsDisabled extends BiometricsPreferenceNotifier {
  @override
  bool build() => false;
}

class _RemovalApi extends RestoredWalletApi {
  _RemovalApi({KeyTypeInfo keyType = KeyTypeInfo.importedSpending}) {
    keys
      ..clear()
      ..add(
        KeyGroupInfo(
          id: 2,
          label: 'Legacy savings',
          keyType: keyType,
          spendable: keyType != KeyTypeInfo.importedViewing,
          hasSapling: true,
          hasIronwood: false,
          birthdayHeight: 100,
          createdAt: 1788220800,
        ),
      );
    visibleKeyCount = 1;
    addresses
      ..clear()
      ..[2] = 'zs1exampleimportedkeyaddressnotforpayments';
  }

  final verifiedPassphrases = <String>[];
  final removals = <(String, int)>[];
  final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  bool rejectRemoval = false;

  @override
  Future<List<AddressBalanceInfo>> crateApiListAddressBalances({
    required String walletId,
    int? keyId,
  }) async => [
    AddressBalanceInfo(
      address: addresses[2]!,
      keyId: 2,
      addressId: 2,
      diversifierIndex: 0,
      createdAt: createdAt,
      balance: BigInt.zero,
      spendable: BigInt.zero,
      pending: BigInt.zero,
      colorTag: AddressBookColorTag.none,
    ),
  ];

  @override
  Future<bool> crateApiVerifyAppPassphrase({required String passphrase}) async {
    verifiedPassphrases.add(passphrase);
    return passphrase == 'correct passphrase';
  }

  @override
  Future<void> crateApiRemoveImportedSpendingKey({
    required String walletId,
    required int keyId,
  }) async {
    removals.add((walletId, keyId));
    if (rejectRemoval) throw StateError('Wallet is still syncing');
  }
}

class _Harness {
  _Harness(this.api);

  final _RemovalApi api;
  late final GoRouter router;

  Future<void> pump(
    WidgetTester tester, {
    bool light = false,
    bool capture = false,
  }) async {
    RustLib.initMock(api: api);
    router = GoRouter(
      initialLocation: '/settings/keys/detail?keyId=2',
      routes: [
        GoRoute(
          path: '/settings/keys',
          builder: (_, _) => const Scaffold(body: Text('Keys home')),
        ),
        GoRoute(
          path: '/settings/keys/detail',
          builder: (_, _) => const KeyDetailScreen(keyId: 2),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWalletProvider.overrideWith(_Wallet.new),
          decoyModeProvider.overrideWith(_Mode.new),
          biometricsEnabledProvider.overrideWith(_BiometricsDisabled.new),
          biometricAvailabilityProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp.router(
          theme: light ? PTheme.light() : PTheme.dark(),
          routerConfig: router,
          builder: (context, child) {
            AppColors.syncWithTheme(Theme.of(context).brightness);
            if (child == null) return const SizedBox.shrink();
            return capture
                ? RepaintBoundary(key: _captureKey, child: child)
                : child;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() {
    router.dispose();
    RustLib.dispose();
  }
}

Future<void> _revealRemoveButton(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.widgetWithText(PButton, 'Remove imported key'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openConfirmation(WidgetTester tester) async {
  await _revealRemoveButton(tester);
  await tester.tap(find.widgetWithText(PButton, 'Remove imported key'));
  await tester.pumpAndSettle();
  expect(find.text('Remove imported key?'), findsOneWidget);
}

Future<void> _continueToPassphrase(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  expect(find.text('Verify passphrase'), findsOneWidget);
}

Future<void> _capture(
  WidgetTester tester,
  String filename,
  Finder finder,
) async {
  final directory = Platform.environment['PIRATE_UI_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  Directory(directory).createSync(recursive: true);
  await expectLater(
    finder,
    matchesGoldenFile(Uri.file('$directory${Platform.pathSeparator}$filename')),
  );
}

void main() {
  testWidgets('recovery phrase and viewing keys have no removal control', (
    tester,
  ) async {
    for (final type in [KeyTypeInfo.seed, KeyTypeInfo.importedViewing]) {
      final harness = _Harness(_RemovalApi(keyType: type));
      await harness.pump(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('Remove imported key'), findsNothing);
      expect(harness.api.removals, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    }
  });

  testWidgets('cancel leaves the imported key in place', (tester) async {
    final harness = _Harness(_RemovalApi());
    await harness.pump(tester);
    addTearDown(harness.dispose);
    await _openConfirmation(tester);
    expect(find.textContaining('Legacy savings'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Remove imported key?'), findsNothing);
    expect(harness.api.verifiedPassphrases, isEmpty);
    expect(harness.api.removals, isEmpty);
  });

  testWidgets('requires passphrase before removing the selected key', (
    tester,
  ) async {
    final harness = _Harness(_RemovalApi());
    await harness.pump(tester);
    addTearDown(harness.dispose);
    await _openConfirmation(tester);
    await _continueToPassphrase(tester);

    await tester.enterText(find.byType(TextField).last, 'incorrect');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.text('Passphrase is incorrect'), findsOneWidget);
    expect(harness.api.removals, isEmpty);

    await tester.enterText(find.byType(TextField).last, 'correct passphrase');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(harness.api.verifiedPassphrases, [
      'incorrect',
      'correct passphrase',
    ]);
    expect(harness.api.removals, [('removal-test-wallet', 2)]);
    expect(find.text('Keys home'), findsOneWidget);
  });

  testWidgets('removal failure stays on key and shows an error', (
    tester,
  ) async {
    final api = _RemovalApi()..rejectRemoval = true;
    final harness = _Harness(api);
    await harness.pump(tester);
    addTearDown(harness.dispose);
    await _openConfirmation(tester);
    await _continueToPassphrase(tester);
    await tester.enterText(find.byType(TextField).last, 'correct passphrase');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(api.removals, [('removal-test-wallet', 2)]);
    expect(
      find.textContaining('Could not remove imported key:'),
      findsOneWidget,
    );
    expect(find.text('Keys home'), findsNothing);
  });

  testWidgets(
    'captures imported key detail and confirmation on phone and desktop',
    (tester) async {
      if (Platform.environment['PIRATE_UI_CAPTURE_DIR'] == null) return;
      for (final light in [false, true]) {
        for (final desktop in [false, true]) {
          debugDefaultTargetPlatformOverride = desktop
              ? TargetPlatform.windows
              : TargetPlatform.android;
          PScaffold.debugShowDesktopTitleBar = desktop;
          tester.view.physicalSize = desktop
              ? const Size(1280, 900)
              : const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          final harness = _Harness(_RemovalApi());
          await harness.pump(tester, light: light, capture: true);
          await _revealRemoveButton(tester);
          final suffix =
              '${desktop ? 'desktop' : 'phone'}-${light ? 'light' : 'dark'}';
          await _capture(
            tester,
            'imported-key-detail-$suffix.png',
            find.byKey(_captureKey),
          );
          await _openConfirmation(tester);
          await _capture(
            tester,
            'imported-key-remove-confirm-$suffix.png',
            find.byType(Overlay).first,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          harness.dispose();
        }
      }
      PScaffold.debugShowDesktopTitleBar = false;
      debugDefaultTargetPlatformOverride = null;
      AppColors.syncWithTheme(Brightness.dark);
      tester.view.reset();
    },
  );

  setUpAll(() async {
    if (Platform.environment['PIRATE_UI_CAPTURE_DIR'] == null) return;
    final sora = FontLoader('Sora')
      ..addFont(rootBundle.load('assets/fonts/Sora/Sora.ttf'));
    await sora.load();
    final mono = FontLoader(
      'JetBrainsMono',
    )..addFont(rootBundle.load('assets/fonts/JetBrainsMono/JetBrainsMono.ttf'));
    await mono.load();
    final materialIconsPath =
        Platform.environment['PIRATE_MATERIAL_ICONS_FONT'];
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        materialIconsPath == null
            ? rootBundle.load('fonts/MaterialIcons-Regular.otf')
            : File(materialIconsPath).readAsBytes().then(ByteData.sublistView),
      );
    await icons.load();
  });
}
