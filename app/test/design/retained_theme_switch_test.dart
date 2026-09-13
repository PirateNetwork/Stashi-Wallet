import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/design/theme.dart';
import 'package:pirate_wallet/design/themes/default_palette.dart';
import 'package:pirate_wallet/design/tokens/colors.dart';
import 'package:pirate_wallet/ui/molecules/p_card.dart';
import 'package:pirate_wallet/ui/organisms/balance_hero.dart';
import 'package:pirate_wallet/ui/organisms/p_nav.dart';

void main() {
  testWidgets(
    'retained macOS widgets follow light/dark changes and local previews',
    (tester) async {
      final mode = ValueNotifier(ThemeMode.light);
      addTearDown(mode.dispose);
      // Deliberately wrong global palette: these widgets must resolve Theme,
      // including when the router retains their instances across a switch.
      AppColors.syncWithTheme(Brightness.dark);
      final retained = Row(
        children: [
          PNav(
            currentIndex: 0,
            onDestinationSelected: (_) {},
            destinations: const [
              PNavDestination(icon: Icons.home, label: 'Home'),
              PNavDestination(icon: Icons.list, label: 'Activity'),
            ],
          ),
          const Expanded(
            child: Column(
              children: [
                PCard(child: Text('Card')),
                BalanceHero(balanceText: '12 ARRR'),
              ],
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ValueListenableBuilder(
          valueListenable: mode,
          builder: (_, value, _) => MaterialApp(
            theme: PTheme.light(),
            darkTheme: PTheme.dark(),
            themeMode: value,
            themeAnimationDuration: Duration.zero,
            home: Scaffold(body: retained),
          ),
        ),
      );
      final cardState = tester.state(find.byType(PCard));
      for (final next in [ThemeMode.light, ThemeMode.dark, ThemeMode.light]) {
        mode.value = next;
        await tester.pumpAndSettle();
        final palette = next == ThemeMode.light
            ? defaultLightPalette
            : defaultDarkPalette;
        expect(tester.state(find.byType(PCard)), same(cardState));
        final container = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(PCard),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (container.decoration! as BoxDecoration).color,
          palette.backgroundSurface,
        );
        expect(
          tester.widget<Text>(find.text('12 ARRR')).style!.color,
          palette.textPrimary,
        );
        expect(
          tester.widget<Text>(find.text('Activity')).style!.color,
          palette.textSecondary,
        );
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );
}
