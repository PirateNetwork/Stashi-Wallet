import 'package:pirate_wallet/routes/app_router.dart';
import 'package:pirate_wallet/ui/organisms/p_scaffold.dart';

import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:pirate_wallet/core/ffi/generated/frb_generated.dart';
import 'package:pirate_wallet/core/ffi/generated/models.dart' as native;
import 'package:pirate_wallet/features/address_book/address_book_screen.dart';
import 'package:pirate_wallet/features/address_book/address_book_detail_screen.dart';
import 'package:pirate_wallet/features/address_book/models/address_entry.dart';
import 'package:pirate_wallet/features/address_book/providers/address_book_provider.dart';
import 'package:pirate_wallet/features/keys/key_detail_screen.dart';
import 'package:pirate_wallet/features/keys/consolidate_key_screen.dart';
import 'package:pirate_wallet/features/keys/sweep_key_screen.dart';
import 'package:pirate_wallet/features/unlock/unlock_screen.dart';
import 'package:pirate_wallet/features/payment_disclosure/payment_disclosure_verifier_screen.dart';
import 'package:pirate_wallet/features/onboarding/screens/passphrase_setup_screen.dart';
import 'package:pirate_wallet/features/onboarding/screens/biometrics_screen.dart';
import 'package:pirate_wallet/features/settings/export_seed_screen.dart';
import 'package:pirate_wallet/features/settings/panic_pin_screen.dart';
import 'package:pirate_wallet/features/settings/watch_only_screen.dart';
import 'package:pirate_wallet/features/settings/screens/biometrics_screen.dart';
import 'package:pirate_wallet/features/settings/screens/passphrase_change_screen.dart';
import 'package:pirate_wallet/features/settings/screens/theme_screen.dart';
import 'package:pirate_wallet/features/settings/screens/currency_screen.dart';
import 'package:pirate_wallet/features/settings/screens/language_screen.dart';
import 'package:pirate_wallet/features/settings/screens/seed_phrase_language_screen.dart';
import 'package:pirate_wallet/features/settings/screens/swap_interface_screen.dart';
import 'package:pirate_wallet/features/settings/screens/terms_screen.dart';
import 'package:pirate_wallet/features/settings/screens/licenses_screen.dart';
import 'package:pirate_wallet/features/swap/swap_screen.dart';
import 'package:pirate_wallet/features/swap/swap_viewmodel.dart';

import 'support/restored_wallet_api.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pirate_wallet/features/receive/widgets/address_qr_widget.dart';
import 'package:pirate_wallet/ui/atoms/p_input.dart';
import 'package:pirate_wallet/core/ffi/ffi_bridge.dart';
import 'package:pirate_wallet/core/ffi/generated/models.dart'
    hide AddressInfo, NodeTestResult;
import 'package:pirate_wallet/core/providers/connection_status_provider.dart';
import 'package:pirate_wallet/core/providers/price_providers.dart';
import 'package:pirate_wallet/core/providers/wallet_providers.dart';
import 'package:pirate_wallet/core/services/address_rotation_service.dart';
import 'package:pirate_wallet/core/security/decoy_data.dart';
import 'package:pirate_wallet/core/swaps/swap_providers.dart';
import 'package:pirate_wallet/design/theme.dart';
import 'package:pirate_wallet/design/tokens/colors.dart';
import 'package:pirate_wallet/features/app_shell/app_shell.dart';
import 'package:pirate_wallet/features/activity/activity_screen.dart';
import 'package:pirate_wallet/features/activity/transaction_detail_screen.dart';
import 'package:pirate_wallet/features/home/home_screen.dart';
import 'package:pirate_wallet/features/keys/import_spending_key_screen.dart';
import 'package:pirate_wallet/features/keys/keys_screen.dart';
import 'package:pirate_wallet/features/onboarding/screens/backup_warning_screen.dart';
import 'package:pirate_wallet/features/onboarding/screens/birthday_picker_screen.dart';
import 'package:pirate_wallet/features/onboarding/screens/create_or_import_screen.dart';
import 'package:pirate_wallet/features/onboarding/screens/ivk_import_screen.dart';
import 'package:pirate_wallet/features/onboarding/screens/seed_confirm_screen.dart';
import 'package:pirate_wallet/features/onboarding/screens/seed_display_screen.dart';
import 'package:pirate_wallet/features/onboarding/screens/seed_import_screen.dart';
import 'package:pirate_wallet/features/onboarding/screens/welcome_screen.dart';
import 'package:pirate_wallet/features/onboarding/onboarding_flow.dart';
import 'package:pirate_wallet/features/pay/pay_screen.dart';
import 'package:pirate_wallet/features/receive/receive_screen.dart';
import 'package:pirate_wallet/features/receive/receive_viewmodel.dart';
import 'package:pirate_wallet/features/send/send_screen.dart';
import 'package:pirate_wallet/features/settings/providers/transport_providers.dart';
import 'package:pirate_wallet/features/settings/providers/preferences_providers.dart';
import 'package:pirate_wallet/features/settings/screens/birthday_height_screen.dart';
import 'package:pirate_wallet/features/settings/screens/node_settings_screen.dart';
import 'package:pirate_wallet/features/settings/screens/outbound_api_screen.dart';
import 'package:pirate_wallet/features/settings/screens/privacy_shield_screen.dart';
import 'package:pirate_wallet/features/settings/settings_screen.dart';

const _captureBoundaryKey = ValueKey('guide-capture-boundary');

class _ActiveWallet extends ActiveWalletNotifier {
  @override
  String? build() => 'guide-wallet';
}

class _NormalMode extends DecoyModeNotifier {
  @override
  bool build() => false;
}

class _GuideOnboardingController extends OnboardingController {
  _GuideOnboardingController(this.initialState);

  final OnboardingState initialState;

  @override
  OnboardingState build() => initialState;
}

class _GuideReceiveViewModel extends ReceiveViewModel {
  @override
  ReceiveState build() => ReceiveState(
    currentAddress: 'zs1stashi9x4y0ku3z7g5m2r8e6p0q4w7t9n3c5v8b2x6a0s4d7f9h3j5k8l2p6q0w4e7r9t',
    addressHistory: [
      AddressInfo(
        addressId: 2,
        address:
            'zs1savings6u4x8m2p9r5w3t7y0q4e8k2n6c9v3b7a5d1f8h4j0l6s2g9z5x3m7p',
        label: 'Savings',
        createdAt: DateTime(2026, 8, 28),
        diversifierIndex: 2,
        balance: BigInt.from(72500000000),
      ),
      AddressInfo(
        addressId: 1,
        address:
            'zs1payments3m8x5q2w9e6r4t7y0u1i5o8p3a6s9d2f4g7h0j5k8l1z6x9c2v4b7n',
        label: 'Payments',
        createdAt: DateTime(2026, 8, 20),
        diversifierIndex: 1,
        wasUsedForReceive: true,
      ),
    ],
    diversifierIndex: 3,
  );
}

class _DirectTunnelMode extends TunnelModeNotifier {
  @override
  TunnelMode build() => const TunnelMode.direct();
}

class _ReadyTorStatus extends TorStatusNotifier {
  @override
  TorStatusDetails build() => const TorStatusDetails(status: 'ready');
}

class _DarkThemeMode extends ThemeModeNotifier {
  @override
  AppThemeMode build() => AppThemeMode.dark;
}

class _LightThemeMode extends ThemeModeNotifier {
  @override
  AppThemeMode build() => AppThemeMode.light;
}

class _TorTransport extends TransportConfigNotifier {
  @override
  TransportConfig build() => const TransportConfig(
    mode: 'tor',
    dnsProvider: 'system',
    socks5Config: <String, String?>{},
    i2pEndpoint: 'http://5vjlbxmzx4gjfuwcot2qtfjdnxodzpe4jsw3ckx7i4maltz7j5qa.b32.i2p:9067',
    tlsPins: <Map<String, String>>[],
    torBridge: TorBridgeConfig(
      useBridges: false,
      fallbackToBridges: false,
      transport: 'snowflake',
      bridgeLines: <String>[],
      transportPath: null,
    ),
  );
}

const _walletMeta = WalletMeta(
  id: 'guide-wallet',
  name: 'My ARRR Wallet 1',
  createdAt: 1787961600,
  watchOnly: false,
  birthdayHeight: 3500000,
  networkType: 'mainnet',
);

const _guideMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon art';

final _guideTransactions = [
  TxInfo(
    txid: 'e89060e026faec5713f9fbdcb80647fc9c13815ebcdafff052d8c225545bddff',
    height: 4111812,
    timestamp: DateTime(2026, 8, 30).millisecondsSinceEpoch ~/ 1000,
    amount: 2200000000000,
    fee: BigInt.zero,
    memo: 'Treasure Chest migration',
    confirmed: true,
    expired: false,
  ),
  TxInfo(
    txid: '75f2860f6bc123de772e795ec561adb44492c87e73f2a76d204955c046f9efad',
    height: 4111020,
    timestamp: DateTime(2026, 8, 27).millisecondsSinceEpoch ~/ 1000,
    amount: -12500000000,
    fee: BigInt.from(10000),
    memo: 'Invoice 1042',
    confirmed: true,
    expired: false,
  ),
];

class _GuideActivityHistory extends ActivityHistoryNotifier {
  @override
  Future<ActivityHistoryState> build() async => ActivityHistoryState(
    transactions: List.unmodifiable(_guideTransactions),
    nextCursor: null,
  );
}

final _syncedStatus = SyncStatus(
  localHeight: BigInt.from(4111871),
  targetHeight: BigInt.from(4111871),
  percent: 100,
  eta: null,
  stage: SyncStage.verify,
  lastCheckpoint: null,
  blocksPerSecond: 0,
  notesDecrypted: BigInt.from(8),
  lastBatchMs: BigInt.zero,
);

Widget _walletApp(
  Widget child, {
  bool unlocked = false,
  bool includeReceiveState = false,
  bool includeAppVersion = false,
  bool light = false,
  double textScale = 1,
  Balance? balance,
  SyncStatus? syncStatus,
}) {
  return ProviderScope(
    overrides: [
      if (unlocked) ...[
        walletsExistProvider.overrideWith((ref) async => true),
        hasAppPassphraseProvider.overrideWith((ref) async => true),
        appUnlockedProvider.overrideWith(_ReviewUnlocked.new),
      ],
      activeWalletProvider.overrideWith(_ActiveWallet.new),
      decoyModeProvider.overrideWith(_NormalMode.new),
      activeWalletMetaProvider.overrideWithValue(_walletMeta),
      walletsProvider.overrideWith((ref) async => const [_walletMeta]),
      balanceStreamProvider.overrideWith(
        (ref) => Stream.value(
          balance ??
              Balance(
                total: BigInt.from(2247523456789),
                spendable: BigInt.from(2247523456789),
                pending: BigInt.zero,
              ),
        ),
      ),
      syncProgressStreamProvider.overrideWith(
        (ref) => Stream.value(syncStatus ?? _syncedStatus),
      ),
      syncStatusProvider.overrideWith(
        (ref) async => syncStatus ?? _syncedStatus,
      ),
      transactionsProvider.overrideWith((ref) async => _guideTransactions),
      activityHistoryProvider.overrideWith(_GuideActivityHistory.new),
      transactionStreamProvider.overrideWith((ref) => const Stream.empty()),
      transactionWatcherProvider.overrideWith((ref) {}),
      syncCompletionWatcherProvider.overrideWith((ref) {}),
      autoRotationWatcherProvider.overrideWith((ref) {}),
      syncCompletionRotationWatcherProvider.overrideWith((ref) {}),
      walletInitRotationWatcherProvider.overrideWith((ref) {}),
      kdfSwapWarmupProvider.overrideWith((ref) {}),
      appThemeModeProvider.overrideWith(
        light ? _LightThemeMode.new : _DarkThemeMode.new,
      ),
      // Representative fixture quote, never a live market-price assertion.
      arrrPriceQuoteProvider.overrideWith(
        (ref) => Stream.value(
          ArrrPriceQuote(
            currency: CurrencyPreference.usd,
            pricePerArrr: 0.25,
            fetchedAt: DateTime(2026, 9, 8),
            source: ArrrPriceSource.coingecko,
          ),
        ),
      ),
      decoySyncHeightProvider.overrideWith((ref) async => 0),
      tunnelModeProvider.overrideWith(_DirectTunnelMode.new),
      torStatusProvider.overrideWith(_ReadyTorStatus.new),
      transportConfigProvider.overrideWith(_TorTransport.new),
      connectionStatusLevelProvider.overrideWithValue(
        ConnectionStatusLevel.secure,
      ),
      lightdEndpointConfigProvider.overrideWith(
        (ref) async =>
            const LightdEndpointConfig(url: 'https://lightd1.pirate.black:443'),
      ),
      if (includeReceiveState)
        receiveViewModelProvider.overrideWith(_GuideReceiveViewModel.new),
      if (includeAppVersion)
        appVersionProvider.overrideWith((ref) async => 'v1.1.9'),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: light ? PTheme.light() : PTheme.dark(),
      builder: (context, child) {
        AppColors.syncWithTheme(Theme.of(context).brightness);
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: RepaintBoundary(key: _captureBoundaryKey, child: child),
    ),
  );
}

Widget _app(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PTheme.dark(),
      home: RepaintBoundary(key: _captureBoundaryKey, child: child),
    ),
  );
}

Widget _onboardingApp(Widget child, OnboardingState state) {
  return ProviderScope(
    overrides: [
      onboardingControllerProvider.overrideWith(
        () => _GuideOnboardingController(state),
      ),
      walletsProvider.overrideWith((ref) async => const <WalletMeta>[]),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PTheme.dark(),
      home: RepaintBoundary(key: _captureBoundaryKey, child: child),
    ),
  );
}

Future<void> _capture(
  WidgetTester tester, {
  required Size size,
  required String filename,
  required Widget widget,
  TargetPlatform platform = TargetPlatform.android,
  Future<void> Function(WidgetTester tester)? interact,
  bool captureOverlay = false,
  bool allowKnownBaselineOverflow = false,
  void Function(WidgetTester)? verify,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  PScaffold.debugShowDesktopTitleBar = platform == TargetPlatform.windows;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(widget);
  await tester.pump(const Duration(milliseconds: 900));
  // Let short data-arrival transitions finish before taking a still image.
  await tester.pump(const Duration(milliseconds: 250));
  if (interact != null) {
    await interact(tester);
    await tester.pumpAndSettle();
  }
  verify?.call(tester);

  final outputDirectory = Platform.environment['PIRATE_UI_CAPTURE_DIR'];
  if (outputDirectory != null && outputDirectory.isNotEmpty) {
    final path = '$outputDirectory${Platform.pathSeparator}$filename';
    await expectLater(
      captureOverlay
          ? find.byType(Overlay).first
          : find.byKey(_captureBoundaryKey),
      matchesGoldenFile(Uri.file(path)),
    );
  }

  final exception = tester.takeException();
  if (allowKnownBaselineOverflow && exception != null) {
    expect(exception.toString(), contains('overflowed'));
  } else {
    expect(exception, isNull);
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  PScaffold.debugShowDesktopTitleBar = false;
  debugDefaultTargetPlatformOverride = null;
  AppColors.syncWithTheme(Brightness.dark);
  tester.view.reset();
}

Future<void> _captureWelcome(
  WidgetTester tester, {
  required Size size,
  required String filename,
  required TargetPlatform platform,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  PScaffold.debugShowDesktopTitleBar = platform == TargetPlatform.windows;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final router = GoRouter(
    initialLocation: '/onboarding/welcome',
    routes: [
      GoRoute(
        path: '/onboarding/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: PTheme.dark(),
        routerConfig: router,
        builder: (context, child) => RepaintBoundary(
          key: _captureBoundaryKey,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/icons/stashi-wallet-logo.png'),
      tester.element(find.byType(WelcomeScreen)),
    );
  });
  await tester.pumpAndSettle();

  final logo = find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName ==
            'assets/icons/stashi-wallet-logo.png',
  );
  expect(logo, findsOneWidget);
  expect(tester.getSize(logo).isEmpty, isFalse);
  final logoTopLeft = tester.getTopLeft(logo);
  expect(logoTopLeft.dx, greaterThanOrEqualTo(0));
  expect(logoTopLeft.dy, greaterThanOrEqualTo(0));
  expect(logoTopLeft.dx, lessThan(size.width));
  expect(logoTopLeft.dy, lessThan(size.height));

  final outputDirectory = Platform.environment['PIRATE_UI_CAPTURE_DIR'];
  if (outputDirectory != null && outputDirectory.isNotEmpty) {
    final path = '$outputDirectory${Platform.pathSeparator}$filename';
    await expectLater(
      find.byKey(_captureBoundaryKey),
      matchesGoldenFile(Uri.file(path)),
    );
  }
  expect(tester.takeException(), isNull);
  router.dispose();
  await tester.pumpWidget(const SizedBox.shrink());
  PScaffold.debugShowDesktopTitleBar = false;
  debugDefaultTargetPlatformOverride = null;
  tester.view.reset();
}

class _ReviewUnlocked extends AppUnlockedNotifier {
  @override
  bool build() => true;
}

class _ReviewRoutes extends ConsumerStatefulWidget {
  const _ReviewRoutes();
  @override
  ConsumerState<_ReviewRoutes> createState() => _ReviewRoutesState();
}

class _ReviewRoutesState extends ConsumerState<_ReviewRoutes> {
  late final GoRouter _router;
  @override
  void initState() {
    super.initState();
    _router = ref.read(appRouterProvider);
    _router.go('/settings/address-book');
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(theme: PTheme.dark(), routerConfig: _router);
}

void main() {
  testWidgets(
    'address book Send opens the real Send route with its recipient',
    (tester) async {
      RustLib.initMock(api: _ReviewApi());
      addTearDown(RustLib.dispose);
      await tester.pumpWidget(
        _walletApp(const _ReviewRoutes(), unlocked: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex'));
      await tester.pumpAndSettle();
      final send = find.text('Send to This Address');
      await tester.ensureVisible(send);
      await tester.pumpAndSettle();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(find.byType(SendScreen), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'zs1samplecontactaddressnotforpayments',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'contact picker fills only the chosen recipient and preserves amounts',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      RustLib.initMock(api: _ReviewApi());
      addTearDown(RustLib.dispose);
      await tester.pumpWidget(_walletApp(const SendScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '10');
      await tester.ensureVisible(find.text('Add recipient'));
      await tester.tap(find.text('Add recipient'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(3), '3');
      final picker = find.byTooltip('Address Book').last;
      await tester.ensureVisible(picker);
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex'));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields[0].controller!.text, isEmpty);
      expect(fields[1].controller!.text, '10');
      expect(
        fields[2].controller!.text,
        'zs1samplecontactaddressnotforpayments',
      );
      expect(fields[3].controller!.text, '3');
      expect(tester.takeException(), isNull);
    },
  );
  _registerReviewCaptures();
  testWidgets('send review stays reachable above keyboard', (tester) async {
    addTearDown(tester.view.reset);
    RustLib.initMock(api: _ReviewApi());
    addTearDown(RustLib.dispose);
    await _capture(
      tester,
      size: const Size(320, 640),
      filename: 'send-keyboard-phone.png',
      widget: _walletApp(const SendScreen()),
      interact: (tester) async {
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump();
        await tester.enterText(find.byType(TextField).at(1), '10');
        await tester.scrollUntilVisible(
          find.text('Review transaction'),
          180,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Review transaction').hitTestable(), findsOneWidget);
      },
    );
  });

  testWidgets('captures send review states', (tester) async {
    RustLib.initMock(api: _ReviewApi());
    addTearDown(RustLib.dispose);
    for (final desktop in [false, true]) {
      await _capture(
        tester,
        size: desktop ? const Size(1280, 900) : const Size(390, 844),
        filename: 'send-review-${desktop ? 'desktop' : 'phone'}.png',
        platform: desktop ? TargetPlatform.windows : TargetPlatform.android,
        widget: _walletApp(const SendScreen()),
        interact: (tester) async {
          final fields = find.byType(TextField);
          await tester.enterText(
            fields.at(0),
            'zs1stashi9x4y0ku3z7g5m2r8e6p0q4w7t9n3c5v8b2x6a0s4d7f9h3j5k8l2p6q0w4e7r9t',
          );
          await tester.enterText(fields.at(1), '12345.12345678');
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.ensureVisible(find.text('Review transaction'));
          await tester.tap(find.text('Review transaction'));
          await tester.pumpAndSettle();
          expect(find.text('Unlock to send'), findsOneWidget);
        },
      );
    }
  });

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/local_auth'),
          (call) async {
            if (call.method == 'getAvailableBiometrics') {
              return <String>[];
            }
            return false;
          },
        );

    final sora = FontLoader('Sora')
      ..addFont(rootBundle.load('assets/fonts/Sora/Sora.ttf'));
    await sora.load();
    final monospace = FontLoader(
      'JetBrainsMono',
    )..addFont(rootBundle.load('assets/fonts/JetBrainsMono/JetBrainsMono.ttf'));
    await monospace.load();
    final systemMono = FontLoader(
      'monospace',
    )..addFont(rootBundle.load('assets/fonts/JetBrainsMono/JetBrainsMono.ttf'));
    await systemMono.load();

    final materialIconsPath =
        Platform.environment['PIRATE_MATERIAL_ICONS_FONT'];
    // Fail instead of silently rendering missing-glyph squares in screenshots.
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(
        materialIconsPath == null
            ? rootBundle.load('fonts/MaterialIcons-Regular.otf')
            : File(materialIconsPath).readAsBytes().then(ByteData.sublistView),
      );
    await materialIcons.load();
  });

  tearDown(() {
    PScaffold.debugShowDesktopTitleBar = false;
    debugDefaultTargetPlatformOverride = null;
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/local_auth'),
          null,
        );
  });

  testWidgets('captures changed wallet pages in light mode', (tester) async {
    for (final desktop in [false, true]) {
      final suffix = desktop ? 'desktop' : 'phone';
      final size = desktop ? const Size(1280, 900) : const Size(390, 844);
      final platform = desktop
          ? TargetPlatform.windows
          : TargetPlatform.android;
      final pages = <String, Widget>{
        'home': const AppShell(
          location: '/home',
          child: HomeScreen(useScaffold: false),
        ),
        'activity': const AppShell(
          location: '/activity',
          child: ActivityScreen(useScaffold: false),
        ),
        'receive': const ReceiveScreen(),
        'spending-key-import': const ImportSpendingKeyScreen(),
      };
      for (final page in pages.entries) {
        await _capture(
          tester,
          size: size,
          filename: '${page.key}-$suffix-light.png',
          widget: _walletApp(
            page.value,
            light: true,
            includeReceiveState: page.key == 'receive',
          ),
          platform: platform,
          verify: (tester) {
            expect(
              AppColors.backgroundBase,
              PTheme.light().scaffoldBackgroundColor,
            );
            if (page.key == 'home') {
              expect(find.text(r'USD $5,618.81'), findsOneWidget);
            }
          },
        );
      }
    }
  });

  testWidgets(
    'captures pending funds and active sync with full balance content',
    (tester) async {
      final scanning = SyncStatus(
        localHeight: BigInt.from(4000000),
        targetHeight: BigInt.from(4111871),
        percent: 97.28,
        eta: BigInt.from(54),
        stage: SyncStage.notes,
        lastCheckpoint: null,
        blocksPerSecond: 2048,
        notesDecrypted: BigInt.from(120),
        lastBatchMs: BigInt.from(40),
      );
      for (final desktop in [false, true]) {
        await _capture(
          tester,
          size: desktop ? const Size(1280, 900) : const Size(390, 844),
          filename: desktop
              ? 'home-pending-desktop.png'
              : 'home-pending-phone.png',
          widget: _walletApp(
            const AppShell(
              location: '/home',
              child: HomeScreen(useScaffold: false),
            ),
            balance: Balance(
              total: BigInt.from(2247523456789),
              spendable: BigInt.from(2246523456789),
              pending: BigInt.from(1000000000),
            ),
            syncStatus: scanning,
          ),
          platform: desktop ? TargetPlatform.windows : TargetPlatform.android,
          verify: (tester) {
            expect(find.text(r'USD $5,618.81'), findsOneWidget);
            expect(find.text('Pending: 10.00000000 ARRR'), findsOneWidget);
            expect(find.text('97.3%'), findsOneWidget);
          },
        );
      }
    },
  );

  testWidgets('captures receive request and verifies its complete QR payload', (
    tester,
  ) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'receive-request-phone.png',
      widget: _walletApp(const ReceiveScreen(), includeReceiveState: true),
      interact: (tester) async {
        await tester.tap(find.text('Payment request (optional)'));
        await tester.pumpAndSettle();
        Finder field(String label) => find.descendant(
          of: find.widgetWithText(PInput, label),
          matching: find.byType(TextField),
        );
        await tester.enterText(field('Amount'), '1.23456789');
        await tester.enterText(field('Memo (optional)'), 'Invoice 1042');
        await tester.pumpAndSettle();
        final uri = Uri.parse(
          tester.widget<AddressQRWidget>(find.byType(AddressQRWidget)).qrData!,
        );
        expect(uri.scheme, 'pirate');
        expect(uri.queryParameters, {
          'amount': '1.23456789',
          'memo': 'Invoice 1042',
        });
        await tester.ensureVisible(find.text('Clear request'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear request'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Payment request (optional)'),
          -250,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        // The sliver can dispose an offscreen request section after its clear
        // action shrinks it. Reopen it if it was rebuilt in its collapsed state.
        if (field('Amount').evaluate().isEmpty) {
          await tester.tap(find.text('Payment request (optional)'));
          await tester.pumpAndSettle();
        }
        expect(
          tester.widget<TextField>(field('Amount')).controller!.text,
          isEmpty,
        );
        expect(
          tester.widget<TextField>(field('Memo (optional)')).controller!.text,
          isEmpty,
        );
        await tester.enterText(field('Amount'), '1.23456789');
        await tester.enterText(field('Memo (optional)'), 'Invoice 1042');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.ensureVisible(find.text('Payment request (optional)'));
        // Leave breathing room below the fixed app bar in the review capture.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 64));
      },
    );
  });

  testWidgets('captures onboarding on phone and desktop', (tester) async {
    await _captureWelcome(
      tester,
      size: const Size(1280, 900),
      filename: 'welcome-desktop.png',
      platform: TargetPlatform.windows,
    );
    await _captureWelcome(
      tester,
      size: const Size(390, 844),
      filename: 'welcome-phone.png',
      platform: TargetPlatform.android,
    );
  });

  testWidgets('captures home on phone and desktop', (tester) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'home-phone.png',
      widget: _walletApp(
        const AppShell(
          location: '/home',
          child: HomeScreen(useScaffold: false),
        ),
      ),
      verify: (tester) => expect(find.text(r'USD $5,618.81'), findsOneWidget),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'home-desktop.png',
      widget: _walletApp(
        const AppShell(
          location: '/home',
          child: HomeScreen(useScaffold: false),
        ),
      ),
      verify: (tester) => expect(find.text(r'USD $5,618.81'), findsOneWidget),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures wallet hub on phone and desktop', (tester) async {
    final sheet = PaySheet(
      onSend: () {},
      onReceive: () {},
      onVerify: () {},
      onSwap: () {},
    );
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'pay-phone.png',
      widget: _app(Scaffold(body: sheet)),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'pay-desktop.png',
      widget: _app(
        Scaffold(
          body: Center(child: SizedBox(width: 780, child: sheet)),
        ),
      ),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures send on phone and desktop', (tester) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'send-phone.png',
      widget: _walletApp(const SendScreen()),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'send-desktop.png',
      widget: _walletApp(const SendScreen()),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures receive on phone and desktop', (tester) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'receive-phone.png',
      widget: _walletApp(const ReceiveScreen(), includeReceiveState: true),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'receive-desktop.png',
      widget: _walletApp(const ReceiveScreen(), includeReceiveState: true),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures key management on phone and desktop', (tester) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'keys-phone.png',
      widget: _walletApp(
        KeyManagementScreen(keyLoader: (_) async => DecoyData.keyGroups()),
      ),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'keys-desktop.png',
      widget: _walletApp(
        KeyManagementScreen(keyLoader: (_) async => DecoyData.keyGroups()),
      ),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures network privacy on phone and desktop', (tester) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'network-privacy-phone.png',
      widget: _walletApp(const PrivacyShieldScreen()),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'network-privacy-desktop.png',
      widget: _walletApp(const PrivacyShieldScreen()),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures settings on phone and desktop', (tester) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'settings-phone.png',
      widget: _walletApp(const SettingsScreen(), includeAppVersion: true),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'settings-desktop.png',
      widget: _walletApp(const SettingsScreen(), includeAppVersion: true),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures wallet setup choices on phone and desktop', (
    tester,
  ) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'setup-choices-phone.png',
      widget: _app(const CreateOrImportScreen()),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'setup-choices-desktop.png',
      widget: _app(const CreateOrImportScreen()),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures seed import on phone and desktop', (tester) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'seed-import-phone.png',
      widget: _app(const SeedImportScreen()),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'seed-import-desktop.png',
      widget: _app(const SeedImportScreen()),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures backup warning on phone and desktop', (tester) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'backup-warning-phone.png',
      widget: _app(const BackupWarningScreen()),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'backup-warning-desktop.png',
      widget: _app(const BackupWarningScreen()),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures recovery phrase language on phone and desktop', (
    tester,
  ) async {
    const state = OnboardingState(
      currentStep: OnboardingStep.seedDisplay,
      mode: OnboardingMode.create,
      mnemonic: _guideMnemonic,
      mnemonicLanguage: MnemonicLanguage.english,
    );
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'seed-display-phone.png',
      widget: _onboardingApp(const SeedDisplayScreen(), state),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'seed-display-desktop.png',
      widget: _onboardingApp(const SeedDisplayScreen(), state),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures wallet naming and seed confirmation', (tester) async {
    const state = OnboardingState(
      currentStep: OnboardingStep.seedConfirm,
      mode: OnboardingMode.create,
      mnemonic: _guideMnemonic,
      mnemonicLanguage: MnemonicLanguage.english,
    );
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'seed-confirm-phone.png',
      widget: _onboardingApp(const SeedConfirmScreen(), state),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'seed-confirm-desktop.png',
      widget: _onboardingApp(const SeedConfirmScreen(), state),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures restore naming and birthday selection', (tester) async {
    const state = OnboardingState(
      currentStep: OnboardingStep.birthdayPicker,
      mode: OnboardingMode.import,
      mnemonic: _guideMnemonic,
      mnemonicLanguage: MnemonicLanguage.english,
      passphrase: 'local-only-test-passphrase',
    );
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'wallet-birthday-phone.png',
      widget: _onboardingApp(const BirthdayPickerScreen(), state),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'wallet-birthday-desktop.png',
      widget: _onboardingApp(const BirthdayPickerScreen(), state),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures compact Ubuntu laptop layouts', (tester) async {
    await _capture(
      tester,
      size: const Size(1097, 706),
      filename: 'home-laptop.png',
      widget: _walletApp(
        const AppShell(
          location: '/home',
          child: HomeScreen(useScaffold: false),
        ),
      ),
      platform: TargetPlatform.linux,
    );
    await _capture(
      tester,
      size: const Size(1097, 706),
      filename: 'wallets-laptop.png',
      widget: _walletApp(
        const AppShell(location: '/pay', child: PayScreen(useScaffold: false)),
      ),
      platform: TargetPlatform.linux,
    );
  });

  testWidgets('captures activity on phone and desktop', (tester) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'activity-phone.png',
      widget: _walletApp(
        const AppShell(
          location: '/activity',
          child: ActivityScreen(useScaffold: false),
        ),
      ),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'activity-desktop.png',
      widget: _walletApp(
        const AppShell(
          location: '/activity',
          child: ActivityScreen(useScaffold: false),
        ),
      ),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures transaction details on phone and desktop', (
    tester,
  ) async {
    final details = TransactionDetailScreen(
      txid: _guideTransactions.first.txid,
      transaction: _guideTransactions.first,
    );
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'transaction-details-phone.png',
      widget: _walletApp(details),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'transaction-details-desktop.png',
      widget: _walletApp(details),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures seed account help on phone and desktop', (
    tester,
  ) async {
    Future<void> openHelp(WidgetTester tester) async {
      await tester.tap(find.text('How seed accounts work'));
    }

    Widget keys() => _walletApp(
      KeyManagementScreen(keyLoader: (_) async => DecoyData.keyGroups()),
    );
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'seed-account-help-phone.png',
      widget: keys(),
      interact: openHelp,
      captureOverlay: true,
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'seed-account-help-desktop.png',
      widget: keys(),
      platform: TargetPlatform.windows,
      interact: openHelp,
      captureOverlay: true,
    );
  });

  testWidgets('captures spending-key import on phone and desktop', (
    tester,
  ) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'spending-key-import-phone.png',
      widget: _walletApp(const ImportSpendingKeyScreen()),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'spending-key-import-desktop.png',
      widget: _walletApp(const ImportSpendingKeyScreen()),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures view-only wallet fields on mobile and desktop', (
    tester,
  ) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'view-only-wallet-mobile.png',
      widget: _walletApp(const ViewingKeysImportScreen()),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'view-only-wallet-desktop.png',
      widget: _walletApp(const ViewingKeysImportScreen()),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures viewing-key import on mobile and desktop', (
    tester,
  ) async {
    Future<void> openViewingKeyImport(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Viewing Key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Viewing Key'));
    }

    Widget keys() => _walletApp(
      KeyManagementScreen(keyLoader: (_) async => DecoyData.keyGroups()),
    );
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'viewing-key-import-mobile.png',
      widget: keys(),
      interact: openViewingKeyImport,
      captureOverlay: true,
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'viewing-key-import-desktop.png',
      widget: keys(),
      platform: TargetPlatform.windows,
      interact: openViewingKeyImport,
      captureOverlay: true,
    );
  });

  testWidgets('captures node selection on phone and desktop', (tester) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'node-selection-phone.png',
      widget: _walletApp(const NodeSettingsScreen()),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'node-selection-desktop.png',
      widget: _walletApp(const NodeSettingsScreen()),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures outbound API controls on phone and desktop', (
    tester,
  ) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'outbound-apis-phone.png',
      widget: _walletApp(const OutboundApiScreen()),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'outbound-apis-desktop.png',
      widget: _walletApp(const OutboundApiScreen()),
      platform: TargetPlatform.windows,
    );
  });

  testWidgets('captures birthday height on phone and desktop', (tester) async {
    await _capture(
      tester,
      size: const Size(390, 844),
      filename: 'birthday-height-phone.png',
      widget: _walletApp(BirthdayHeightScreen(nodeTester: _guideNodeTester)),
    );
    await _capture(
      tester,
      size: const Size(1280, 900),
      filename: 'birthday-height-desktop.png',
      widget: _walletApp(BirthdayHeightScreen(nodeTester: _guideNodeTester)),
      platform: TargetPlatform.windows,
    );
  });
}

Future<NodeTestResult> _guideNodeTester({
  required String url,
  String? tlsPin,
}) async => NodeTestResult(
  success: true,
  latestBlockHeight: 4111871,
  transportMode: 'tor',
  tlsEnabled: true,
  tlsPinMatched: true,
  responseTimeMs: 86,
  serverVersion: 'lightwalletd',
  chainName: 'main',
);

// Read-only fixtures for visual review. No real wallet, secrets or network.
class _ReviewApi extends RestoredWalletApi {
  @override
  Future<SpendabilityStatus> crateApiGetSpendabilityStatus({
    required String walletId,
  }) async => SpendabilityStatus(
    spendable: true,
    rescanRequired: false,
    targetHeight: BigInt.from(4111871),
    anchorHeight: BigInt.from(4111871),
    validatedAnchorHeight: BigInt.from(4111871),
    repairQueued: false,
    reasonCode: '',
  );
  @override
  Future<PendingTx> crateApiBuildTx({
    required String walletId,
    required List<Output> outputs,
    BigInt? feeOpt,
  }) async {
    final total = outputs.fold(
      BigInt.zero,
      (sum, output) => sum + output.amount,
    );
    final fee = feeOpt ?? BigInt.from(10000);
    return PendingTx(
      id: 'visual-review-only',
      outputs: outputs,
      totalAmount: total,
      fee: fee,
      change: BigInt.zero,
      inputTotal: total + fee,
      numInputs: 2,
      expiryHeight: 4111891,
      createdAt: 1788134400,
    );
  }

  @override
  Future<bool> crateApiHasDuressPassphrase() async => false;

  @override
  Future<bool> crateApiHasAppPassphrase() async => true;

  @override
  Future<List<native.AddressBookEntryFfi>> crateApiListAddressBook({
    required String walletId,
  }) async => [
    native.AddressBookEntryFfi(
      id: 1,
      walletId: walletId,
      address: 'zs1samplecontactaddressnotforpayments',
      label: 'Alex',
      notes: 'Monthly studio rent',
      colorTag: native.AddressBookColorTag.blue,
      isFavorite: true,
      createdAt: 1788220800,
      updatedAt: 1788220800,
      useCount: 3,
    ),
  ];
}

class _ReviewSwap extends SwapViewModel {
  @override
  SwapViewModelState build() => SwapViewModelState(
    payAmountText: '0.25',
    fundingLtcBalance: Decimal.parse('1.5'),
    fundingArrrBalance: Decimal.parse('250'),
  );

  @override
  Future<void> refreshFundingBalances({bool clearMessages = true}) async {}

  @override
  Future<void> refreshOrderbook() async {}
}

class _ReviewContacts extends AddressBookNotifier {
  _ReviewContacts(this.contact);
  final AddressEntry contact;
  @override
  AddressBookState build() => AddressBookState(entries: [contact]);
}

class _ReviewDebugLogging extends DebugLoggingPreferenceNotifier {
  @override
  bool build() => true;
}

Future<void> _openReviewOverlay(WidgetTester tester, String page) async {
  if (page == 'send-contact-picker') {
    await tester.tap(find.byTooltip('Address Book'));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
  } else if (page == 'contact-add') {
    await tester.tap(find.text('Add Address'));
  } else if (page == 'debug-logging') {
    await tester.scrollUntilVisible(
      find.text('Debug logging'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Debug logging'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug logging'));
    await tester.pumpAndSettle();
    expect(
      find.text('Share a redacted copy or clear the current log.'),
      findsOneWidget,
    );
  }
}

void _registerReviewCaptures() {
  final contact = AddressEntry(
    id: 1,
    walletId: 'guide-wallet',
    address: 'zs1samplecontactaddressnotforpayments',
    label: 'Alex',
    notes: 'Monthly studio rent',
    createdAt: DateTime(2026, 8, 30),
    updatedAt: DateTime(2026, 8, 30),
    colorTag: ColorTag.blue,
  );
  final pages = <String, Widget Function()>{
    'transaction': () => TransactionDetailScreen(
      txid: _guideTransactions.first.txid,
      transaction: _guideTransactions.first,
    ),
    'send': () => const SendScreen(),
    'send-contact-picker': () => const SendScreen(),
    'receive': () => const ReceiveScreen(),
    'activity': () => const AppShell(
      location: '/activity',
      child: ActivityScreen(useScaffold: false),
    ),
    'contact-picker': () => const AddressBookScreen(),
    'contact-add': () => const AddressBookScreen(),
    'debug-logging': () => const AppShell(
      location: '/settings',
      child: SettingsScreen(useScaffold: false),
    ),
    'contact-detail': () => AddressBookDetailScreen(entry: contact),
    'contact-edit': () =>
        AddressBookEditScreen(walletId: 'guide-wallet', entry: contact),
    'keys': () => const KeyManagementScreen(),
    'key-detail': () => const KeyDetailScreen(keyId: 1),
    'consolidate': () => const ConsolidateKeyScreen(keyId: 1),
    'sweep': () => const SweepKeyScreen(keyId: 1),
    'private-key': () => const ImportSpendingKeyScreen(),
    'viewing-key': () => const ViewingKeysImportScreen(),
    'watch-only': () => const WatchOnlyScreen(),
    'settings': () => const AppShell(
      location: '/settings',
      child: SettingsScreen(useScaffold: false),
    ),
    'network': () => const PrivacyShieldScreen(),
    'external-connections': () => const OutboundApiScreen(),
    'node': () => const NodeSettingsScreen(),
    'recovery-height': () => BirthdayHeightScreen(nodeTester: _guideNodeTester),
    'unlock': () => const UnlockScreen(),
    'duress': () => const PanicPinScreen(),
    'backup': () => const ExportSeedScreen(
      walletId: 'guide-wallet',
      walletName: 'My ARRR Wallet',
    ),
    'biometrics': () => const BiometricsScreen(),
    'passphrase': () => const PassphraseChangeScreen(),
    'setup-passphrase': () => const PassphraseSetupScreen(),
    'setup-biometrics': () => const OnboardingBiometricsScreen(),
    'setup-choices': () => const CreateOrImportScreen(),
    'restore-phrase': () => const SeedImportScreen(),
    'backup-warning': () => const BackupWarningScreen(),
    'theme': () => const ThemeScreen(),
    'currency': () => const CurrencyScreen(),
    'language': () => const LanguageScreen(),
    'phrase-language': () => const SeedPhraseLanguageScreen(),
    'swap-preferences': () => const SwapInterfaceScreen(),
    'terms': () => const TermsScreen(),
    'licenses': () => const LicensesScreen(),
    'payment-proof': () => const PaymentDisclosureVerifierScreen(),
    'swap': () => const SwapScreen(),
  };
  for (final page in pages.entries) {
    testWidgets('responsive review ${page.key}', (tester) async {
      RustLib.initMock(api: _ReviewApi());
      addTearDown(RustLib.dispose);
      await _capture(
        tester,
        size: const Size(320, 844),
        filename: 'responsive-${page.key}-phone.png',
        captureOverlay:
            page.key == 'contact-add' ||
            page.key == 'debug-logging' ||
            page.key == 'send-contact-picker',
        interact:
            page.key == 'contact-add' ||
                page.key == 'debug-logging' ||
                page.key == 'send-contact-picker'
            ? (tester) => _openReviewOverlay(tester, page.key)
            : null,
        widget: _walletApp(
          ProviderScope(
            overrides: [
              debugLoggingProvider.overrideWith(_ReviewDebugLogging.new),
              addressBookProvider('guide-wallet')
                  .overrideWith(() => _ReviewContacts(contact)),
              swapViewModelProvider.overrideWith(_ReviewSwap.new),
              syncLogsProvider.overrideWith((ref) async => []),
              lastCheckpointProvider.overrideWith((ref) async => null),
              arrrUsdPriceQuoteProvider.overrideWith(
                (ref) => const Stream.empty(),
              ),
              ltcUsdPriceQuoteProvider.overrideWith(
                (ref) => const Stream.empty(),
              ),
            ],
            child: page.value(),
          ),
          textScale: 1.6,
          includeReceiveState: true,
          includeAppVersion: true,
        ),
      );
    });
    testWidgets('review capture ${page.key}', (tester) async {
      RustLib.initMock(api: _ReviewApi());
      addTearDown(RustLib.dispose);
      for (final light in [false, true]) {
        for (final desktop in [false, true]) {
          await _capture(
            tester,
            size: desktop ? const Size(1280, 900) : const Size(390, 844),
            filename:
                'review-${page.key}-${desktop ? 'desktop' : 'phone'}-${light ? 'light' : 'dark'}.png',
            allowKnownBaselineOverflow:
                page.key == 'contacts' &&
                Platform.environment['PIRATE_REVIEW_BASELINE'] == 'true',
            platform: desktop ? TargetPlatform.windows : TargetPlatform.android,
            captureOverlay:
                page.key == 'contact-add' ||
                page.key == 'debug-logging' ||
                page.key == 'send-contact-picker',
            interact:
                page.key == 'contact-add' ||
                    page.key == 'debug-logging' ||
                    page.key == 'send-contact-picker'
                ? (tester) => _openReviewOverlay(tester, page.key)
                : null,
            widget: _walletApp(
              ProviderScope(
                overrides: [
                  debugLoggingProvider.overrideWith(_ReviewDebugLogging.new),
                  addressBookProvider('guide-wallet')
                      .overrideWith(() => _ReviewContacts(contact)),
                  swapViewModelProvider.overrideWith(_ReviewSwap.new),
                  syncLogsProvider.overrideWith((ref) async => []),
                  lastCheckpointProvider.overrideWith((ref) async => null),
                  arrrUsdPriceQuoteProvider.overrideWith(
                    (ref) => const Stream.empty(),
                  ),
                  ltcUsdPriceQuoteProvider.overrideWith(
                    (ref) => const Stream.empty(),
                  ),
                ],
                child: page.value(),
              ),
              light: light,
              includeReceiveState: true,
              includeAppVersion: true,
            ),
          );
        }
      }
    });
  }
}
