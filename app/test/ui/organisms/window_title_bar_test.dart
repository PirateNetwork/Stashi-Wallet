import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/design/theme.dart';
import 'package:pirate_wallet/ui/organisms/p_scaffold.dart';

void main() {
  final calls = <String>[];
  var maximized = false;
  const channel = MethodChannel('window_manager');

  setUp(() {
    calls.clear();
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'isFullScreen') return false;
          if (call.method == 'isMaximized') return maximized;
          if (call.method == 'maximize') maximized = true;
          if (call.method == 'unmaximize') maximized = false;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: PTheme.dark(),
      home: const Scaffold(body: PWindowTitleBar(title: 'Stashi Wallet')),
    ),
  );

  testWidgets('controls minimize, toggle maximize and request graceful close', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.crop_square));
    await tester.pumpAndSettle();
    expect(maximized, isTrue);
    await tester.tap(find.byIcon(Icons.crop_square));
    await tester.pumpAndSettle();
    expect(maximized, isFalse);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(calls, [
      'minimize',
      'isMaximized',
      'maximize',
      'isMaximized',
      'unmaximize',
      'close',
    ]);
  });

  testWidgets('title remains draggable and double tap toggles maximize', (
    tester,
  ) async {
    await pump(tester);
    final title = find.text('Stashi Wallet');
    await tester.drag(title, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(calls, contains('startDragging'));
    calls.clear();
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(calls, ['isMaximized', 'maximize']);
    expect(tester.takeException(), isNull);
  });
}
