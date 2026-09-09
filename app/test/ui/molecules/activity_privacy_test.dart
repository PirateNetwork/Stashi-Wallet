import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/ui/molecules/transaction_row_v2.dart';

void main() {
  testWidgets('activity never reveals a memo in text or accessibility labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionRowV2(
            isReceived: true,
            isConfirmed: true,
            amountText: '+1 ARRR',
            timestamp: DateTime(2026, 9, 1),
            memo: 'private-memo-fixture',
            compactHistory: true,
          ),
        ),
      ),
    );
    expect(find.textContaining('private-memo-fixture'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('private-memo-fixture|Has memo')),
      findsNothing,
    );
    expect(find.text('Has memo'), findsNothing);
    expect(find.text('Confirmed'), findsOneWidget);
    semantics.dispose();
  });
}
