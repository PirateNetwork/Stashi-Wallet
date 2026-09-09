import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/ui/molecules/viewing_key_fields.dart';

void main() {
  testWidgets('one field detects the pool and clears the previous pool', (
    tester,
  ) async {
    final sapling = TextEditingController();
    final ironwood = TextEditingController();
    addTearDown(sapling.dispose);
    addTearDown(ironwood.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ViewingKeyFields(
            saplingController: sapling,
            ironwoodController: ironwood,
          ),
        ),
      ),
    );
    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    await tester.enterText(field, 'zxviews1sample');
    expect(sapling.text, 'zxviews1sample');
    expect(ironwood.text, isEmpty);
    await tester.enterText(field, 'pirate-extended-viewing-key1sample');
    expect(sapling.text, isEmpty);
    expect(ironwood.text, 'pirate-extended-viewing-key1sample');
    await tester.enterText(field, '');
    expect(sapling.text, isEmpty);
    expect(ironwood.text, isEmpty);
  });
}
