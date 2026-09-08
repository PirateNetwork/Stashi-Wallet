import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/ffi/ffi_bridge.dart';
import 'package:pirate_wallet/core/ffi/generated/models.dart';
import 'package:pirate_wallet/core/providers/price_providers.dart';
import 'package:pirate_wallet/core/providers/wallet_providers.dart';
import 'package:pirate_wallet/design/theme.dart';
import 'package:pirate_wallet/design/tokens/spacing.dart';
import 'package:pirate_wallet/features/home/home_screen.dart';
import 'package:pirate_wallet/features/settings/providers/transport_providers.dart';
import 'package:pirate_wallet/features/settings/providers/preferences_providers.dart';
import 'package:pirate_wallet/ui/molecules/transaction_row_v2.dart';
import 'package:pirate_wallet/ui/organisms/balance_hero.dart';

import '../../support/test_font_loader.dart';

class _TestTunnelModeNotifier extends TunnelModeNotifier {
  @override
  TunnelMode build() => const TunnelMode.direct();
}

class _TestTorStatusNotifier extends TorStatusNotifier {
  @override
  TorStatusDetails build() => const TorStatusDetails(status: 'ready');
}

class _TestTransportConfigNotifier extends TransportConfigNotifier {
  @override
  TransportConfig build() => const TransportConfig(
    mode: 'direct',
    dnsProvider: 'cloudflare_doh',
    socks5Config: {},
    i2pEndpoint: '',
    tlsPins: [],
    torBridge: TorBridgeConfig(
      useBridges: false,
      fallbackToBridges: true,
      transport: 'snowflake',
      bridgeLines: [],
      transportPath: null,
    ),
  );
}

Widget _testApp({
  BigInt? total,
  BigInt? pending,
  List<TxInfo> transactions = const [],
  Key? key,
  double textScale = 1,
  Future<List<TxInfo>> Function()? loadTransactions,
  Stream<Balance>? balanceStream,
}) {
  final syncedStatus = SyncStatus(
    localHeight: BigInt.from(4100000),
    targetHeight: BigInt.from(4100000),
    percent: 100,
    eta: null,
    stage: SyncStage.verify,
    lastCheckpoint: null,
    blocksPerSecond: 0,
    notesDecrypted: BigInt.zero,
    lastBatchMs: BigInt.zero,
  );

  return ProviderScope(
    retry: (_, _) => null,
    key: key,
    overrides: [
      activeWalletMetaProvider.overrideWithValue(
        WalletMeta(
          id: 'wallet-1',
          name: 'My Stashi Wallet',
          createdAt: 0,
          watchOnly: false,
          birthdayHeight: 3500000,
          networkType: 'mainnet',
        ),
      ),
      balanceStreamProvider.overrideWith(
        (ref) =>
            balanceStream ??
            Stream.value(
              Balance(
                total: total ?? BigInt.from(100000000),
                spendable: BigInt.from(100000000),
                pending: pending ?? BigInt.zero,
              ),
            ),
      ),
      syncProgressStreamProvider.overrideWith(
        (ref) => Stream.value(syncedStatus),
      ),
      syncStatusProvider.overrideWith((ref) async => syncedStatus),
      transactionsProvider.overrideWith(
        (ref) async =>
            loadTransactions == null ? transactions : await loadTransactions(),
      ),
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
      tunnelModeProvider.overrideWith(_TestTunnelModeNotifier.new),
      torStatusProvider.overrideWith(_TestTorStatusNotifier.new),
      transportConfigProvider.overrideWith(_TestTransportConfigNotifier.new),
      lightdEndpointConfigProvider.overrideWith(
        (ref) async =>
            const LightdEndpointConfig(url: 'https://lightd1.pirate.black:443'),
      ),
    ],
    child: MaterialApp(
      theme: PTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(body: HomeScreen(useScaffold: false)),
    ),
  );
}

void main() {
  setUpAll(() async {
    await loadTestFont('Sora', 'assets/fonts/Sora/Sora.ttf');
    await loadTestFont(
      'JetBrainsMono',
      'assets/fonts/JetBrainsMono/JetBrainsMono.ttf',
    );
  });

  testWidgets('sizes the header to include fiat and pending balance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_testApp(key: const ValueKey('settled')));
    await tester.pumpAndSettle();
    final settled = tester.getSize(find.byType(BalanceHero)).height;
    expect(find.text(r'USD $0.25'), findsOneWidget);
    await tester.pumpWidget(
      _testApp(pending: BigInt.from(50000000), key: const ValueKey('pending')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(BalanceHero)).height,
      greaterThan(settled),
    );
    final fiat = tester.getRect(find.text(r'USD $0.25'));
    final pending = tester.getRect(find.text('Pending: 0.50000000 ARRR'));
    expect(pending.top, greaterThanOrEqualTo(fiat.bottom));
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1097, 706),
    const Size(1280, 900),
  ]) {
    testWidgets(
      'shows fiat and pending without overflow at $size with enlarged text',
      (tester) async {
        debugDefaultTargetPlatformOverride = size.width > 1000
            ? TargetPlatform.linux
            : TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _testApp(pending: BigInt.from(50000000), textScale: 1.6),
        );
        await tester.pumpAndSettle();
        expect(find.text(r'USD $0.25'), findsOneWidget);
        expect(find.text('Pending: 0.50000000 ARRR'), findsOneWidget);
        final hero = tester.getRect(find.byType(BalanceHero));
        final pending = tester.getRect(find.text('Pending: 0.50000000 ARRR'));
        expect(pending.bottom, lessThanOrEqualTo(hero.bottom));
        await tester.ensureVisible(find.text('Receive'));
        await tester.pumpAndSettle();
        expect(find.text('Receive').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('lets the balance scroll away to leave room for activity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    final before = tester
        .getTopLeft(find.byKey(HomeScreen.headerSurfaceKey))
        .dy;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(HomeScreen.headerSurfaceKey)).dy,
      lessThan(before),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed activity offers retry instead of claiming the wallet is empty',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _testApp(
          loadTransactions: () async {
            calls++;
            if (calls == 1) throw StateError('native diagnostics');
            return [];
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No activity yet'), findsNothing);
      expect(find.textContaining('native diagnostics'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('No activity yet'), findsOneWidget);
    },
  );

  testWidgets('an unavailable balance is never displayed as zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(balanceStream: Stream.error(StateError('unavailable'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Balance unavailable'), findsOneWidget);
    expect(find.text('0.00000000 ARRR'), findsNothing);
    expect(find.text('Share your address to get paid.'), findsNothing);
  });
  testWidgets('keeps long recent amounts clear and separates mobile cards', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final transactions = [
      TxInfo(
        txid: 'large-receive',
        height: 4099999,
        timestamp: timestamp,
        amount: 7799999970000,
        fee: BigInt.zero,
        memo: null,
        confirmed: true,
        expired: false,
      ),
      TxInfo(
        txid: 'large-send',
        height: 4099998,
        timestamp: timestamp - 60,
        amount: -1234567890000,
        fee: BigInt.from(10000),
        memo: null,
        confirmed: true,
        expired: false,
      ),
    ];

    await tester.pumpWidget(_testApp(transactions: transactions));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    final rows = find.byType(TransactionRowV2);
    expect(rows, findsNWidgets(2));
    expect(find.text('+77999.9997 ARRR'), findsOneWidget);
    expect(find.text('-12345.6789 ARRR'), findsOneWidget);

    final first = tester.getRect(rows.at(0));
    final second = tester.getRect(rows.at(1));
    expect(second.top - first.bottom, PSpacing.sm);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
