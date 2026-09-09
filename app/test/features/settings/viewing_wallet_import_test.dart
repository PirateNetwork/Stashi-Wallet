import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/providers/wallet_providers.dart';
import 'package:pirate_wallet/features/settings/watch_only_screen.dart';

void main() {
  testWidgets('imports Ironwood without putting it in the Sapling field', (
    tester,
  ) async {
    String? sapling;
    String? ironwood;
    int? submittedBirthday;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importViewingWalletProvider.overrideWithValue(({
            required String name,
            String? saplingViewingKey,
            String? ironwoodViewingKey,
            required int birthday,
          }) async {
            submittedBirthday = birthday;
            sapling = saplingViewingKey;
            ironwood = ironwoodViewingKey;
            // Stay on the form so the submitted state can be inspected.
            throw StateError('Test import endpoint');
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ImportSaplingViewingKeyTab()),
        ),
      ),
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Watch wallet');
    await tester.enterText(fields.at(1), 'pirate-extended-viewing-key1test');
    await tester.enterText(fields.at(2), '0');
    final submit = find.text('Import view only wallet');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid birthday height'), findsOneWidget);
    expect(ironwood, isNull);
    await tester.enterText(fields.at(2), '100');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(sapling, isNull);
    expect(ironwood, 'pirate-extended-viewing-key1test');
    expect(submittedBirthday, 100);
    expect(tester.takeException(), isNull);
  });
}
