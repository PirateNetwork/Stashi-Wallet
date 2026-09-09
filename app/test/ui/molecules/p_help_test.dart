import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/ui/molecules/p_help.dart';

void main() {
  for (final method in ['tap', 'long press', 'hover']) {
    testWidgets('supplemental help is accessible by $method', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: PHelpButton(topic: 'TLS', message: 'Connection details'),
            ),
          ),
        ),
      );
      final control = find.byType(IconButton);
      if (method == 'hover') {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(control));
        await tester.pump(const Duration(milliseconds: 500));
        addTearDown(mouse.removePointer);
      } else if (method == 'long press') {
        await tester.longPress(control);
      } else {
        await tester.tap(control);
      }
      await tester.pumpAndSettle();
      expect(find.text('Connection details'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Tooltip.dismissAllToolTips();
      await tester.pumpAndSettle();
    });
  }
}
