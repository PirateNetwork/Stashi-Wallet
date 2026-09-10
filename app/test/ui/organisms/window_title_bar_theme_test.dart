import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/design/themes/default_palette.dart';
import 'package:pirate_wallet/design/tokens/colors.dart';
import 'package:pirate_wallet/ui/organisms/p_scaffold.dart';

void main() {
  testWidgets('constant desktop title bar follows live theme changes', (
    tester,
  ) async {
    final textFont = FontLoader('Sora')
      ..addFont(rootBundle.load('assets/fonts/Sora/Sora.ttf'));
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await textFont.load();
    await iconFont.load();
    tester.view.physicalSize = const Size(900, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var light = false;
    late StateSetter rebuild;
    // Leave the compatibility palette dark to verify context-driven colors.
    AppColors.syncWithTheme(Brightness.dark);
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return MaterialApp(
            themeAnimationDuration: Duration.zero,
            theme: ThemeData(
              fontFamily: 'Sora',
              brightness: light ? Brightness.light : Brightness.dark,
              extensions: [
                if (light) defaultLightPalette else defaultDarkPalette,
              ],
            ),
            home: const RepaintBoundary(
              key: ValueKey('theme-capture'),
              child: Scaffold(
                body: Column(
                  children: [
                    PWindowTitleBar(title: 'Stashi Wallet'),
                    Expanded(child: Center(child: Text('Wallet content'))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    final title = find.text('Stashi Wallet');
    expect(
      tester.widget<Text>(title).style!.color,
      defaultDarkPalette.textPrimary,
    );
    rebuild(() => light = true);
    await tester.pumpAndSettle();
    final output = Platform.environment['PIRATE_UI_CAPTURE_DIR'];
    if (output != null) {
      await expectLater(
        find.byKey(const ValueKey('theme-capture')),
        matchesGoldenFile(Uri.file('$output/quality-titlebar-live-light.png')),
      );
    }
    if (Platform.environment['PIRATE_REVIEW_BASELINE'] == 'true') return;
    expect(
      tester.widget<Text>(title).style!.color,
      defaultLightPalette.textPrimary,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.close)).color,
      defaultLightPalette.textPrimary,
    );
    final surface = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(PWindowTitleBar),
            matching: find.byType(Container),
          ),
        )
        .first;
    expect(
      (surface.decoration! as BoxDecoration).color,
      defaultLightPalette.backgroundBase,
    );
  });
}
