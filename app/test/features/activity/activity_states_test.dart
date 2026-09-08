import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/ffi/generated/models.dart';
import 'package:pirate_wallet/core/providers/wallet_providers.dart';
import 'package:pirate_wallet/design/theme.dart';
import 'package:pirate_wallet/features/activity/activity_screen.dart';
import 'package:pirate_wallet/ui/atoms/p_input.dart';
import 'package:pirate_wallet/ui/molecules/transaction_row_v2.dart';

class _History extends ActivityHistoryNotifier {
  _History(this.load);
  final Future<List<TxInfo>> Function() load;
  @override
  Future<ActivityHistoryState> build() async =>
      ActivityHistoryState(transactions: await load(), nextCursor: null);
}

TxInfo _transaction(String id, DateTime date, {int amount = 1}) => TxInfo(
  txid: id,
  height: 10,
  timestamp: date.millisecondsSinceEpoch ~/ 1000,
  amount: amount,
  fee: BigInt.zero,
  memo: null,
  confirmed: true,
  expired: false,
);

Widget _app(Future<List<TxInfo>> Function() load, {double textScale = 1}) {
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      activityHistoryProvider.overrideWith(() => _History(load)),
      syncProgressStreamProvider.overrideWith((ref) => Stream.value(null)),
      syncStatusProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(
      theme: PTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(body: ActivityScreen(useScaffold: false)),
    ),
  );
}

void main() {
  testWidgets(
    'distinguishes no results and resets the search and filter together',
    (tester) async {
      await tester.pumpWidget(
        _app(
          () async => [
            _transaction('received', DateTime.now()),
            _transaction('sent', DateTime.now(), amount: -100000000),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Received').first);
      await tester.enterText(
        find.descendant(
          of: find.byType(PInput),
          matching: find.byType(TextField),
        ),
        'missing',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('No matching transactions'), findsOneWidget);
      expect(find.text('No activity yet'), findsNothing);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionRowV2), findsNWidgets(2));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets('retry recovers activity without exposing native diagnostics', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(() async {
        calls++;
        if (calls == 1) throw StateError('private internal database path');
        return [_transaction('recovered', DateTime.now())];
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load activity'), findsOneWidget);
    expect(find.textContaining('private internal'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(TransactionRowV2), findsOneWidget);
  });

  testWidgets('keeps loading distinct from a zero-transaction history', (
    tester,
  ) async {
    final pending = Completer<List<TxInfo>>();
    await tester.pumpWidget(_app(() => pending.future));
    await tester.pump();
    expect(find.text('Loading activity'), findsOneWidget);
    expect(find.text('No activity yet'), findsNothing);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No activity yet'), findsOneWidget);
    expect(find.text('Receive ARRR'), findsOneWidget);
  });

  testWidgets('groups by local calendar day and preserves the smallest unit', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    await tester.pumpWidget(
      _app(
        () async => [
          _transaction('today-one', today),
          _transaction('today-two', today, amount: -1),
          _transaction(
            'yesterday',
            DateTime(today.year, today.month, today.day - 1),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('+0.00000001 ARRR'), findsNWidgets(2));
    expect(find.text('-0.00000001 ARRR'), findsOneWidget);
  });

  testWidgets('empty state fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(() async => [], textScale: 1.6));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Receive ARRR'));
    await tester.pumpAndSettle();
    expect(find.text('Receive ARRR').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
