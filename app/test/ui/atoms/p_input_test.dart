import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/ui/atoms/p_input.dart';

void main() {
  testWidgets('revealed sensitive input never enables keyboard learning', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PInput(sensitive: true, obscureText: false)),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isFalse);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(field.smartDashesType, SmartDashesType.disabled);
    expect(field.smartQuotesType, SmartQuotesType.disabled);
  });

  testWidgets('visible label is attached to text field semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PInput(label: 'Enter your passphrase', obscureText: true),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Enter your passphrase'), findsOneWidget);
    semantics.dispose();
  });
}
