import 'package:flutter/material.dart';

import '../themes/default_palette.dart';
import '../themes/wallet_palette.dart';
export 'default_colors.dart';

/// Theme-aware app colors (switches between dark and light palettes)
class AppColors {
  AppColors._();

  static Brightness _brightness = Brightness.dark;
  static WalletPalette _dark = defaultDarkPalette;
  static WalletPalette _light = defaultLightPalette;

  /// Compatibility bridge for existing widgets. New widgets should use
  /// WalletPalette.of(context) so nested previews resolve their own palette.
  static void syncWithTheme(
    Brightness brightness, {
    WalletPalette? light,
    WalletPalette? dark,
  }) {
    _brightness = brightness;
    _light = light ?? _light;
    _dark = dark ?? _dark;
  }

  static bool get _isLight => _brightness == Brightness.light;
  static WalletPalette get _palette => _isLight ? _light : _dark;

  // Backgrounds
  static Color get backgroundBase => _palette.backgroundBase;
  static Color get backgroundSurface => _palette.backgroundSurface;
  static Color get backgroundElevated => _palette.backgroundElevated;
  static Color get backgroundPanel => _palette.backgroundPanel;
  static Color get backgroundOverlay => _palette.backgroundOverlay;

  // Accents
  static Color get gradientAStart => _palette.gradientAStart;
  static Color get gradientAEnd => _palette.gradientAEnd;
  static Color get gradientBStart => _palette.gradientBStart;
  static Color get gradientBEnd => _palette.gradientBEnd;
  static Color get gradientCStart => _palette.gradientCStart;
  static Color get gradientCEnd => _palette.gradientCEnd;
  static Color get highlight => _palette.highlight;

  // Text
  static Color get textPrimary => _palette.textPrimary;
  static Color get textSecondary => _palette.textSecondary;
  static Color get textTertiary => _palette.textTertiary;
  static Color get textDisabled => _palette.textDisabled;
  static Color get textOnAccent => _palette.textOnAccent;

  // Semantic
  static Color get success => _palette.success;
  static Color get successBackground => _palette.successBackground;
  static Color get successBorder => _palette.successBorder;
  static Color get warning => _palette.warning;
  static Color get warningBackground => _palette.warningBackground;
  static Color get warningBorder => _palette.warningBorder;
  static Color get error => _palette.error;
  static Color get errorBackground => _palette.errorBackground;
  static Color get errorBorder => _palette.errorBorder;
  static Color get info => _palette.info;
  static Color get infoBackground => _palette.infoBackground;
  static Color get infoBorder => _palette.infoBorder;

  // Interactive
  static Color get focusRing => _palette.focusRing;
  static Color get focusRingSubtle => _palette.focusRingSubtle;
  static Color get hoverOverlay => _palette.hoverOverlay;
  static Color get pressedOverlay => _palette.pressedOverlay;
  static Color get selectedBackground => _palette.selectedBackground;
  static Color get selectedBorder => _palette.selectedBorder;

  // Borders
  static Color get borderDefault => _palette.borderDefault;
  static Color get borderSubtle => _palette.borderSubtle;
  static Color get borderStrong => _palette.borderStrong;
  static Color get divider => _palette.divider;

  // Shadows
  static Color get shadow => _palette.shadow;
  static Color get shadowStrong => _palette.shadowStrong;

  // Special
  static Color get qrBackground => _palette.qrBackground;
  static Color get qrForeground => _palette.qrForeground;

  static List<Color> get chartColors => _palette.chartColors;

  static List<Color> get gradientA => _palette.gradientA;
  static List<Color> get gradientB => _palette.gradientB;
  static List<Color> get gradientC => _palette.gradientC;

  static LinearGradient get gradientALinear => LinearGradient(
    colors: gradientA,
    begin: Alignment.center,
    end: Alignment.bottomRight,
  );

  static Color textOnBackground(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.5 ? const Color(0xFF000000) : const Color(0xF2FFFFFF);
  }

  static Color withOpacity(Color color, double opacity) {
    return color.withValues(alpha: opacity);
  }

  // Back-compat aliases
  static Color get surface => backgroundSurface;
  static Color get surfaceElevated => backgroundElevated;
  static Color get accentPrimary => gradientAStart;
  static Color get accentSecondary => gradientBStart;
  static Color get border => borderDefault;
  static Color get focus => focusRing;
  static Color get hover => hoverOverlay;

  // Deep Space compatibility aliases
  static Color get deepSpace => backgroundBase;
  static Color get void_ => backgroundBase;
  static Color get voidBlack => backgroundBase;
  static Color get nebula => backgroundSurface;
  static Color get cosmos => backgroundElevated;
  static Color get stardust => backgroundPanel;
  static Color get overlay => backgroundOverlay;
  static Color get gradientAMid =>
      Color.lerp(gradientAStart, gradientAEnd, 0.5)!;
  static Color get textMuted => textTertiary;
  static Color get textOnGradient => textOnAccent;
  static Color get glow =>
      gradientAStart.withValues(alpha: _isLight ? 0.28 : 0.4);
  static Color get shadowDeep => shadowStrong;
  static Color get selected => selectedBackground;
}
