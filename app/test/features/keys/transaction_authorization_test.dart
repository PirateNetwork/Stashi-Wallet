import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Int64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/ffi/generated/frb_generated.dart';
import 'package:pirate_wallet/core/ffi/generated/models.dart';
import 'package:pirate_wallet/core/providers/wallet_providers.dart';
import 'package:pirate_wallet/features/keys/consolidate_key_screen.dart';
import 'package:pirate_wallet/features/keys/sweep_key_screen.dart';
import 'package:pirate_wallet/features/settings/providers/preferences_providers.dart';
import 'package:pirate_wallet/ui/atoms/p_button.dart';

import '../../support/restored_wallet_api.dart';

class _Wallet extends ActiveWalletNotifier {
  @override
  String? build() => 'test-wallet';

  void switchWallet() => state = 'other-wallet';
}

class _Mode extends DecoyModeNotifier {
  @override
  bool build() => false;
}

class _NoBiometrics extends BiometricsPreferenceNotifier {
  @override
  bool build() => false;

  @override
  Future<bool> readPersistedValue() async => false;
}

class _Api extends RestoredWalletApi {
  int signatures = 0;
  int broadcasts = 0;
  int verifications = 0;
  bool verificationFails = false;
  Completer<bool>? verification;
  PendingTx? signedPending;

  PendingTx preview(String target) => PendingTx(
    id: 'reviewed-transaction',
    outputs: [Output(addr: target, amount: BigInt.from(100000000), memo: null)],
    totalAmount: BigInt.from(100000000),
    fee: BigInt.from(10000),
    change: BigInt.zero,
    inputTotal: BigInt.from(100010000),
    numInputs: 2,
    expiryHeight: 500,
    createdAt: 1,
  );

  @override
  Future<PendingTx> crateApiBuildSweepTx({
    required String walletId,
    required String targetAddress,
    BigInt? feeOpt,
    Int64List? keyIdsFilter,
    Int64List? addressIdsFilter,
  }) async => preview(targetAddress);

  @override
  Future<PendingTx> crateApiBuildConsolidationTx({
    required String walletId,
    required int keyId,
    required String targetAddress,
    BigInt? feeOpt,
  }) async => preview(targetAddress);

  @override
  Future<bool> crateApiVerifyAppPassphrase({required String passphrase}) async {
    verifications++;
    if (verificationFails) throw StateError('Verification unavailable');
    return verification?.future ?? (passphrase == 'test-only-passphrase');
  }

  SignedTx sign(PendingTx pending) {
    signatures++;
    signedPending = pending;
    return SignedTx(txid: 'test-txid', raw: Uint8List(0), size: BigInt.zero);
  }

  @override
  Future<SignedTx> crateApiSignTxFiltered({
    required String walletId,
    required PendingTx pending,
    Int64List? keyIdsFilter,
    Int64List? addressIdsFilter,
  }) async => sign(pending);

  @override
  Future<SignedTx> crateApiSignTxForKey({
    required String walletId,
    required PendingTx pending,
    required int keyId,
  }) async => sign(pending);

  @override
  Future<String> crateApiBroadcastTx({required SignedTx signed}) async {
    broadcasts++;
    return signed.txid;
  }
}

void main() {
  for (final sweep in [true, false]) {
    group(sweep ? 'Sweep' : 'Consolidation', () {
      late _Api api;
      late ProviderContainer container;

      setUp(() {
        api = _Api();
        RustLib.initMock(api: api);
        container = ProviderContainer.test(
          overrides: [
            activeWalletProvider.overrideWith(_Wallet.new),
            decoyModeProvider.overrideWith(_Mode.new),
            biometricsEnabledProvider.overrideWith(_NoBiometrics.new),
          ],
        );
      });
      tearDown(RustLib.dispose);

      Future<void> confirm(WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1100, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: sweep
                  ? const SweepKeyScreen(keyId: 1)
                  : const ConsolidateKeyScreen(keyId: 1),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (sweep) {
          await tester.enterText(
            find.byType(TextField),
            'zs1external-test-destination',
          );
        }
        await tester.tap(
          find.text(sweep ? 'Preview sweep' : 'Preview consolidation'),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Confirm and send'));
        final confirmButton = tester.widget<PButton>(
          find.ancestor(
            of: find.text('Confirm and send'),
            matching: find.byType(PButton),
          ),
        );
        await tester.tap(find.text('Confirm and send'));
        // Simulate another queued callback before the disabled button rebuilds.
        confirmButton.onPressed!();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(api.signatures, 0);
        expect(api.broadcasts, 0);
      }

      Future<void> enter(WidgetTester tester, String value) async {
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          value,
        );
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
      }

      testWidgets('cancel never signs or broadcasts', (tester) async {
        await confirm(tester);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(api.verifications, 0);
        expect(api.signatures, 0);
        expect(api.broadcasts, 0);
      });

      testWidgets('empty passphrase stays in the prompt without signing', (
        tester,
      ) async {
        await confirm(tester);
        await enter(tester, '');
        expect(find.text('Passphrase is required.'), findsOneWidget);
        expect(api.verifications, 0);
        expect(api.signatures, 0);
      });

      testWidgets('closing the screen during verification prevents signing', (
        tester,
      ) async {
        await confirm(tester);
        api.verification = Completer();
        await enter(tester, 'test-only-passphrase');
        await tester.pumpWidget(const SizedBox());
        api.verification!.complete(true);
        await tester.pumpAndSettle();
        expect(api.signatures, 0);
        expect(api.broadcasts, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('incorrect passphrase never signs or broadcasts', (
        tester,
      ) async {
        await confirm(tester);
        await enter(tester, 'incorrect');
        expect(api.verifications, 1);
        expect(api.signatures, 0);
        expect(api.broadcasts, 0);
        expect(find.text('Invalid passphrase.'), findsOneWidget);
      });

      testWidgets('verification errors fail closed', (tester) async {
        await confirm(tester);
        api.verificationFails = true;
        await enter(tester, 'test-only-passphrase');
        expect(api.signatures, 0);
        expect(api.broadcasts, 0);
      });

      testWidgets('verified passphrase signs reviewed transaction once', (
        tester,
      ) async {
        await confirm(tester);
        await enter(tester, 'test-only-passphrase');
        expect(api.signatures, 1);
        expect(api.broadcasts, 1);
        expect(api.signedPending!.id, 'reviewed-transaction');
        if (sweep) {
          expect(
            api.signedPending!.outputs.single.addr,
            'zs1external-test-destination',
          );
        }
      });

      testWidgets('wallet change during verification prevents signing', (
        tester,
      ) async {
        await confirm(tester);
        api.verification = Completer();
        await enter(tester, 'test-only-passphrase');
        (container.read(activeWalletProvider.notifier) as _Wallet)
            .switchWallet();
        api.verification!.complete(true);
        await tester.pumpAndSettle();
        expect(api.signatures, 0);
        expect(api.broadcasts, 0);
      });
    });
  }
}
