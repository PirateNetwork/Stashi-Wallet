import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/ffi/generated/frb_generated.dart';
import 'package:pirate_wallet/core/ffi/generated/models.dart';
import 'package:pirate_wallet/core/providers/wallet_providers.dart';
import 'package:pirate_wallet/features/keys/key_detail_screen.dart';
import 'package:pirate_wallet/features/receive/receive_viewmodel.dart';

import '../../support/restored_wallet_api.dart';

class _Wallet extends ActiveWalletNotifier {
  @override
  String? build() => 'wallet-a';

  String? get selectedWallet => state;
  set selectedWallet(String? wallet) => state = wallet;
}

class _Mode extends DecoyModeNotifier {
  @override
  bool build() => false;

  void enableDecoy() => state = true;
}

class _BalanceApi extends RestoredWalletApi {
  int amount = 4000;
  int reads = 0;
  bool fail = false;
  Completer<List<AddressBalanceInfo>>? pending;

  List<AddressBalanceInfo> snapshot(String walletId, int keyId) => [
    AddressBalanceInfo(
      address: '$walletId-address-$keyId',
      keyId: keyId,
      addressId: keyId,
      diversifierIndex: 0,
      createdAt: 1788220800,
      balance: BigInt.from(amount) * BigInt.from(100000000),
      spendable: BigInt.from(amount) * BigInt.from(100000000),
      pending: BigInt.zero,
      colorTag: AddressBookColorTag.none,
    ),
  ];

  @override
  Future<List<AddressBalanceInfo>> crateApiListAddressBalances({
    required String walletId,
    int? keyId,
  }) async {
    reads++;
    if (fail) throw StateError('Temporary read failure');
    return pending?.future ?? snapshot(walletId, keyId ?? 1);
  }
}

void main() {
  late _BalanceApi api;
  late ProviderContainer container;

  setUp(() {
    api = _BalanceApi();
    RustLib.initMock(api: api);
    container = ProviderContainer.test(
      overrides: [
        activeWalletProvider.overrideWith(_Wallet.new),
        decoyModeProvider.overrideWith(_Mode.new),
      ],
    );
  });
  tearDown(RustLib.dispose);

  Future<void> openDetails(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: KeyDetailScreen(keyId: 1)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Balance 4000.00000000 ARRR'), findsOneWidget);
  }

  testWidgets('open address updates from 4000 to 8000 without reopening', (
    tester,
  ) async {
    await openDetails(tester);
    api.amount = 8000;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Balance 8000.00000000 ARRR'), findsOneWidget);
    expect(find.text('Balance 4000.00000000 ARRR'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    final reads = api.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(api.reads, reads);
  });

  testWidgets('slow refreshes do not overlap or blank the address list', (
    tester,
  ) async {
    await openDetails(tester);
    api.pending = Completer();
    await tester.pump(const Duration(seconds: 5));
    final reads = api.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(api.reads, reads);
    expect(find.text('Balance 4000.00000000 ARRR'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    api.amount = 8000;
    api.pending!.complete(api.snapshot('wallet-a', 1));
    api.pending = null;
    await tester.pumpAndSettle();
    expect(find.text('Balance 8000.00000000 ARRR'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed refresh retains the balance and retries next tick', (
    tester,
  ) async {
    await openDetails(tester);
    api.fail = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Balance 4000.00000000 ARRR'), findsOneWidget);
    api.fail = false;
    api.amount = 8000;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Balance 8000.00000000 ARRR'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late response cannot restore real balances in decoy mode', (
    tester,
  ) async {
    await openDetails(tester);
    final pending = Completer<List<AddressBalanceInfo>>();
    api.pending = pending;
    await tester.pump(const Duration(seconds: 5));
    (container.read(decoyModeProvider.notifier) as _Mode).enableDecoy();
    await tester.pumpAndSettle();
    pending.complete(api.snapshot('wallet-a', 1));
    api.pending = null;
    await tester.pumpAndSettle();
    expect(find.text('Balance 4000.00000000 ARRR'), findsNothing);
    expect(find.text('Balance 0.00000000 ARRR'), findsOneWidget);
    final reads = api.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(api.reads, reads);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late response cannot replace a newly selected wallet', (
    tester,
  ) async {
    await openDetails(tester);
    final pending = Completer<List<AddressBalanceInfo>>();
    api.pending = pending;
    await tester.pump(const Duration(seconds: 5));
    api.pending = null;
    api.amount = 100;
    (container.read(activeWalletProvider.notifier) as _Wallet).selectedWallet =
        'wallet-b';
    await tester.pumpAndSettle();
    api.amount = 8000;
    pending.complete(api.snapshot('wallet-a', 1));
    await tester.pumpAndSettle();
    expect(find.text('Balance 100.00000000 ARRR'), findsOneWidget);
    expect(find.text('Balance 8000.00000000 ARRR'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'Receive refresh also replaces the per-address balance snapshot',
    () async {
      container.listen(receiveViewModelProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(receiveViewModelProvider).addressHistory.single.balance,
        BigInt.from(400000000000),
      );
      api.amount = 8000;
      await container
          .read(receiveViewModelProvider.notifier)
          .refreshAddressHistory(force: true);
      expect(
        container.read(receiveViewModelProvider).addressHistory.single.balance,
        BigInt.from(800000000000),
      );
    },
  );
}
