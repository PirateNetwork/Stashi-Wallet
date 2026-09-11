import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pirate_wallet/core/ffi/generated/frb_generated.dart';
import 'package:pirate_wallet/core/ffi/generated/models.dart';
import 'package:pirate_wallet/core/providers/wallet_providers.dart';
import 'package:pirate_wallet/features/activity/payment_disclosures_provider.dart';

class _Wallet extends ActiveWalletNotifier {
  @override
  String? build() => 'wallet-a';
}

class _Unlocked extends AppUnlockedNotifier {
  @override
  bool build() => true;
}

class _Api extends Fake implements RustLibApi {
  int calls = 0;
  Completer<List<PaymentDisclosure>> response = Completer();
  @override
  Future<List<PaymentDisclosure>> crateApiExportPaymentDisclosures({
    required String walletId,
    required String txid,
  }) {
    calls++;
    return response.future;
  }
}

void main() {
  final result = [
    PaymentDisclosure(
      disclosureType: 'sapling',
      txid: 'tx-a',
      outputIndex: 0,
      address: 'fixture-address',
      amount: BigInt.one,
      disclosure: 'fixture-proof',
    ),
  ];
  late _Api api;
  late ProviderContainer container;
  final provider = paymentDisclosuresProvider((
    walletId: 'wallet-a',
    txid: 'tx-a',
  ));
  setUp(() {
    api = _Api();
    RustLib.initMock(api: api);
    container = ProviderContainer(
      overrides: [
        activeWalletProvider.overrideWith(_Wallet.new),
        appUnlockedProvider.overrideWith(_Unlocked.new),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    RustLib.dispose();
  });

  test(
    'shares pending requests and reads the native database on reopening',
    () async {
      final subscription = container.listen(provider, (_, _) {});
      final first = container.read(provider.future);
      final second = container.read(provider.future);
      expect(api.calls, 1);
      api.response.complete(result);
      expect(await first, result);
      expect(await second, result);
      subscription.close();
      await container.pump();
      final reopened = container.listen(provider, (_, _) {});
      expect(await container.read(provider.future), result);
      expect(api.calls, 2);
      reopened.close();
    },
  );

  test('locking clears success and unlocking fetches again', () async {
    container.listen(provider, (_, _) {});
    api.response.complete(result);
    expect(await container.read(provider.future), result);
    container.read(appUnlockedProvider.notifier).unlocked = false;
    expect(await container.read(provider.future), isEmpty);
    api.response = Completer()..complete(result);
    container.read(appUnlockedProvider.notifier).unlocked = true;
    expect(await container.read(provider.future), result);
    expect(api.calls, 2);
  });

  test('does not retain a failed request after closing the screen', () async {
    final subscription = container.listen(provider, (_, _) {});
    final pending = container.read(provider.future);
    final failed = expectLater(pending, throwsStateError);
    api.response.completeError(StateError('offline'));
    await failed;
    subscription.close();
    await container.pump();
    api.response = Completer()..complete(result);
    container.listen(provider, (_, _) {});
    expect(await container.read(provider.future), result);
    expect(api.calls, 2);
  });
}
