import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/design/theme.dart';
import 'package:pirate_wallet/design/tokens/colors.dart';
import 'package:pirate_wallet/features/receive/widgets/address_qr_widget.dart';

import '../../support/test_font_loader.dart';

void main() {
  setUpAll(() async {
    await loadTestFont('Sora', 'assets/fonts/Sora/Sora.ttf');
    await loadTestFont(
      'JetBrainsMono',
      'assets/fonts/JetBrainsMono/JetBrainsMono.ttf',
    );
  });

  for (final light in [false, true]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'QR and sharing actions fit a small phone, light=$light scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          AppColors.syncWithTheme(light ? Brightness.light : Brightness.dark);
          var copies = 0;
          var shares = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: light ? PTheme.light() : PTheme.dark(),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AddressQRWidget(
                        address: 'zs1exampleaddressforlayouttestingonly',
                        copyTooltip: 'Copy request',
                        shareTooltip: 'Share request',
                        onCopy: () => copies++,
                        onShare: () => shares++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Copy'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Copy'));
          await tester.ensureVisible(find.text('Share'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Share'));
          expect(copies, 1);
          expect(shares, 1);
          expect(find.byTooltip('Copy request'), findsOneWidget);
          expect(find.byTooltip('Share request'), findsOneWidget);
          expect(tester.takeException(), isNull);
          AppColors.syncWithTheme(Brightness.dark);
        },
      );
    }
  }
}
