import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/design/theme.dart';
import 'package:pirate_wallet/ui/organisms/balance_hero.dart';

void main() {
  testWidgets('hiding removes every balance immediately, including pending', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var hidden = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: PTheme.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => BalanceHero(
              balanceText: '12.34567890 ARRR',
              secondaryText: r'$25.00',
              helperText: 'Pending: 0.12345678 ARRR',
              isHidden: hidden,
              onToggleVisibility: () => setState(() => hidden = !hidden),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Hide balance'));
    await tester.pump(); // No animation time may be required for privacy.
    expect(find.text('12.34567890 ARRR'), findsNothing);
    expect(find.text(r'$25.00'), findsNothing);
    expect(find.text('Pending: 0.12345678 ARRR'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('12.34567890|25.00|0.12345678')),
      findsNothing,
    );
    expect(find.text('*******'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Show balance'));
    await tester.pump();
    expect(find.text('12.34567890 ARRR'), findsOneWidget);
    expect(find.text('Pending: 0.12345678 ARRR'), findsOneWidget);
    semantics.dispose();
  });
}
