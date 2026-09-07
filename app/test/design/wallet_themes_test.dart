import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/design/theme.dart';
import 'package:pirate_wallet/design/themes/theme_registry.dart';
import 'package:pirate_wallet/design/themes/wallet_palette.dart';
import 'package:pirate_wallet/design/tokens/colors.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

void main() {
  test('default theme retains existing light and dark colors', () {
    expect(WalletThemes.all.first, same(WalletThemes.defaultTheme));
    expect(WalletThemes.resolve(null), same(WalletThemes.defaultTheme));
    expect(
      WalletThemes.resolve('removed-theme'),
      same(WalletThemes.defaultTheme),
    );
    expect(PTheme.dark().scaffoldBackgroundColor, PColors.backgroundBase);
    expect(PTheme.light().scaffoldBackgroundColor, PColorsLight.backgroundBase);
    expect(PTheme.dark().colorScheme.primary, const Color(0xFF2B6FF7));
    expect(PTheme.light().colorScheme.primary, const Color(0xFF2B6FF7));
    expect(PTheme.dark().colorScheme.onPrimary, Colors.white);
    expect(PTheme.light().colorScheme.onPrimary, Colors.white);
  });

  test('registry IDs are unique and stable storage identifiers', () {
    expect(
      WalletThemes.all.map((theme) => theme.id).toSet().length,
      WalletThemes.all.length,
    );
    for (final theme in WalletThemes.all) {
      expect(theme.id, matches(RegExp(r'^[a-z][a-z0-9-]*$')));
      expect(WalletThemes.resolve(theme.id), same(theme));
      expect(theme.name, isNotEmpty);
      expect(theme.description, isNotEmpty);
    }
  });

  for (final definition in WalletThemes.all) {
    for (final brightness in Brightness.values) {
      final palette = definition.palette(brightness);
      test(
        '${definition.id} $brightness uses one palette for custom and Material components',
        () {
          final theme = brightness == Brightness.light
              ? PTheme.light(palette: palette)
              : PTheme.dark(palette: palette);
          expect(theme.extension<WalletPalette>(), same(palette));
          expect(theme.colorScheme.primary, palette.gradientAStart);
          expect(theme.scaffoldBackgroundColor, palette.backgroundBase);
          expect(
            theme.inputDecorationTheme.fillColor,
            palette.backgroundSurface,
          );
          AppColors.syncWithTheme(
            brightness,
            light: definition.light,
            dark: definition.dark,
          );
          expect(AppColors.backgroundBase, palette.backgroundBase);
          expect(AppColors.gradientA, palette.gradientA);
          expect(AppColors.textOnAccent, palette.textOnAccent);
        },
      );
      test(
        '${definition.id} $brightness keeps text and semantic colors readable',
        () {
          for (final background in [
            palette.backgroundBase,
            palette.backgroundSurface,
            palette.backgroundElevated,
          ]) {
            expect(
              contrast(palette.textPrimary, background),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              contrast(palette.textSecondary, background),
              greaterThanOrEqualTo(4.5),
            );
          }
          expect(palette.qrBackground, Colors.white);
          expect(palette.qrForeground, Colors.black);
          final original = WalletThemes.defaultTheme.palette(brightness);
          expect(palette.error, original.error);
          expect(palette.warning, original.warning);
          expect(palette.success, original.success);
          if (definition.id != 'default') {
            for (final accent in [
              ...palette.gradientA,
              ...palette.gradientB,
              ...palette.gradientC,
            ]) {
              expect(
                contrast(palette.textOnAccent, accent),
                greaterThanOrEqualTo(4.5),
              );
            }
          }
        },
      );
    }
  }
  tearDown(
    () => AppColors.syncWithTheme(
      Brightness.dark,
      light: WalletThemes.defaultTheme.light,
      dark: WalletThemes.defaultTheme.dark,
    ),
  );
}
