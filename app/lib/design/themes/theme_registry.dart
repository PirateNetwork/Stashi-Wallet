import 'package:flutter/material.dart';

import '../../core/i18n/arb_text_localizer.dart';
import 'default_palette.dart';
import 'wallet_palette.dart';

/// A bundled, reviewed theme. IDs are persisted; never rename an existing ID.
@immutable
class WalletTheme {
  const WalletTheme({
    required this.id,
    required this.nameBuilder,
    required this.descriptionBuilder,
    required this.light,
    required this.dark,
  });

  final String id;
  final String Function() nameBuilder;
  String get name => nameBuilder();
  final String Function() descriptionBuilder;
  String get description => descriptionBuilder();
  final WalletPalette light;
  final WalletPalette dark;

  WalletPalette palette(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;
}

/// Add reviewed theme definitions here. Settings discovers them automatically.
class WalletThemes {
  WalletThemes._();

  static final defaultTheme = WalletTheme(
    id: 'default',
    nameBuilder: () => 'Default'.tr,
    descriptionBuilder: () => 'The original Stashi blue'.tr,
    light: defaultLightPalette,
    dark: defaultDarkPalette,
  );

  static final List<WalletTheme> all = List.unmodifiable([defaultTheme]);

  /// Removed or unknown saved themes fall back to the original appearance.
  static WalletTheme resolve(String? id, {Iterable<WalletTheme>? themes}) =>
      (themes ?? all).firstWhere(
        (theme) => theme.id == id,
        orElse: () => defaultTheme,
      );
}
