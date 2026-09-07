import 'package:flutter/material.dart';
import 'package:pirate_wallet/design/themes/theme_registry.dart';

// Test-only style verifies future contributions without shipping another theme.
final testWalletTheme = WalletTheme(
  id: 'test-teal',
  nameBuilder: () => 'Test Teal',
  descriptionBuilder: () => 'Test fixture',
  light: WalletThemes.defaultTheme.light.copyWith(
    gradientAStart: const Color(0xFF006B60),
    gradientAEnd: const Color(0xFF00564D),
  ),
  dark: WalletThemes.defaultTheme.dark.copyWith(
    gradientAStart: const Color(0xFF006B60),
    gradientAEnd: const Color(0xFF00564D),
  ),
);

final testWalletThemes = [WalletThemes.defaultTheme, testWalletTheme];
