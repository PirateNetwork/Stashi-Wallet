import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/ui/atoms/p_input.dart';

void main() {
  testWidgets(
    'input scroll state does not read expansion state after remount',
    (tester) async {
      final bucket = PageStorageBucket();
      var showInput = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return ListView(
                    children: [
                      ExpansionTile(
                        key: const PageStorageKey('request'),
                        title: const Text('Request'),
                        children: [
                          if (showInput) const PInput(label: 'Amount'),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Request'));
      await tester.pumpAndSettle();
      rebuild(() => showInput = true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), '1.25');
      expect(find.text('1.25'), findsOneWidget);
      expect(tester.getSize(find.byType(TextField)).height, lessThan(150));
    },
  );
}
