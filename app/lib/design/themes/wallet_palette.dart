import 'package:flutter/material.dart';

/// Semantic color contract shared by Material and custom wallet widgets.
@immutable
class WalletPalette extends ThemeExtension<WalletPalette> {
  const WalletPalette({
    required this.backgroundBase,
    required this.backgroundSurface,
    required this.backgroundElevated,
    required this.backgroundPanel,
    required this.backgroundOverlay,
    required this.gradientAStart,
    required this.gradientAEnd,
    required this.gradientBStart,
    required this.gradientBEnd,
    required this.gradientCStart,
    required this.gradientCEnd,
    required this.highlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textOnAccent,
    required this.success,
    required this.successBackground,
    required this.successBorder,
    required this.warning,
    required this.warningBackground,
    required this.warningBorder,
    required this.error,
    required this.errorBackground,
    required this.errorBorder,
    required this.info,
    required this.infoBackground,
    required this.infoBorder,
    required this.focusRing,
    required this.focusRingSubtle,
    required this.hoverOverlay,
    required this.pressedOverlay,
    required this.selectedBackground,
    required this.selectedBorder,
    required this.borderDefault,
    required this.borderSubtle,
    required this.borderStrong,
    required this.divider,
    required this.shadow,
    required this.shadowStrong,
    required this.qrBackground,
    required this.qrForeground,
    required this.chartColors,
  });

  final Color backgroundBase;
  final Color backgroundSurface;
  final Color backgroundElevated;
  final Color backgroundPanel;
  final Color backgroundOverlay;
  final Color gradientAStart;
  final Color gradientAEnd;
  final Color gradientBStart;
  final Color gradientBEnd;
  final Color gradientCStart;
  final Color gradientCEnd;
  final Color highlight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color textOnAccent;
  final Color success;
  final Color successBackground;
  final Color successBorder;
  final Color warning;
  final Color warningBackground;
  final Color warningBorder;
  final Color error;
  final Color errorBackground;
  final Color errorBorder;
  final Color info;
  final Color infoBackground;
  final Color infoBorder;
  final Color focusRing;
  final Color focusRingSubtle;
  final Color hoverOverlay;
  final Color pressedOverlay;
  final Color selectedBackground;
  final Color selectedBorder;
  final Color borderDefault;
  final Color borderSubtle;
  final Color borderStrong;
  final Color divider;
  final Color shadow;
  final Color shadowStrong;
  final Color qrBackground;
  final Color qrForeground;
  final List<Color> chartColors;

  List<Color> get gradientA => [gradientAStart, gradientAEnd];
  List<Color> get gradientB => [gradientBStart, gradientBEnd];
  List<Color> get gradientC => [gradientCStart, gradientCEnd];

  static WalletPalette of(BuildContext context) =>
      Theme.of(context).extension<WalletPalette>()!;

  @override
  WalletPalette copyWith({
    Color? backgroundBase,
    Color? backgroundSurface,
    Color? backgroundElevated,
    Color? backgroundPanel,
    Color? backgroundOverlay,
    Color? gradientAStart,
    Color? gradientAEnd,
    Color? gradientBStart,
    Color? gradientBEnd,
    Color? gradientCStart,
    Color? gradientCEnd,
    Color? highlight,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? textOnAccent,
    Color? success,
    Color? successBackground,
    Color? successBorder,
    Color? warning,
    Color? warningBackground,
    Color? warningBorder,
    Color? error,
    Color? errorBackground,
    Color? errorBorder,
    Color? info,
    Color? infoBackground,
    Color? infoBorder,
    Color? focusRing,
    Color? focusRingSubtle,
    Color? hoverOverlay,
    Color? pressedOverlay,
    Color? selectedBackground,
    Color? selectedBorder,
    Color? borderDefault,
    Color? borderSubtle,
    Color? borderStrong,
    Color? divider,
    Color? shadow,
    Color? shadowStrong,
    Color? qrBackground,
    Color? qrForeground,
    List<Color>? chartColors,
  }) => WalletPalette(
    backgroundBase: backgroundBase ?? this.backgroundBase,
    backgroundSurface: backgroundSurface ?? this.backgroundSurface,
    backgroundElevated: backgroundElevated ?? this.backgroundElevated,
    backgroundPanel: backgroundPanel ?? this.backgroundPanel,
    backgroundOverlay: backgroundOverlay ?? this.backgroundOverlay,
    gradientAStart: gradientAStart ?? this.gradientAStart,
    gradientAEnd: gradientAEnd ?? this.gradientAEnd,
    gradientBStart: gradientBStart ?? this.gradientBStart,
    gradientBEnd: gradientBEnd ?? this.gradientBEnd,
    gradientCStart: gradientCStart ?? this.gradientCStart,
    gradientCEnd: gradientCEnd ?? this.gradientCEnd,
    highlight: highlight ?? this.highlight,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    textDisabled: textDisabled ?? this.textDisabled,
    textOnAccent: textOnAccent ?? this.textOnAccent,
    success: success ?? this.success,
    successBackground: successBackground ?? this.successBackground,
    successBorder: successBorder ?? this.successBorder,
    warning: warning ?? this.warning,
    warningBackground: warningBackground ?? this.warningBackground,
    warningBorder: warningBorder ?? this.warningBorder,
    error: error ?? this.error,
    errorBackground: errorBackground ?? this.errorBackground,
    errorBorder: errorBorder ?? this.errorBorder,
    info: info ?? this.info,
    infoBackground: infoBackground ?? this.infoBackground,
    infoBorder: infoBorder ?? this.infoBorder,
    focusRing: focusRing ?? this.focusRing,
    focusRingSubtle: focusRingSubtle ?? this.focusRingSubtle,
    hoverOverlay: hoverOverlay ?? this.hoverOverlay,
    pressedOverlay: pressedOverlay ?? this.pressedOverlay,
    selectedBackground: selectedBackground ?? this.selectedBackground,
    selectedBorder: selectedBorder ?? this.selectedBorder,
    borderDefault: borderDefault ?? this.borderDefault,
    borderSubtle: borderSubtle ?? this.borderSubtle,
    borderStrong: borderStrong ?? this.borderStrong,
    divider: divider ?? this.divider,
    shadow: shadow ?? this.shadow,
    shadowStrong: shadowStrong ?? this.shadowStrong,
    qrBackground: qrBackground ?? this.qrBackground,
    qrForeground: qrForeground ?? this.qrForeground,
    chartColors: chartColors == null
        ? this.chartColors
        : List.unmodifiable(chartColors),
  );

  @override
  WalletPalette lerp(covariant WalletPalette? other, double t) {
    if (other == null) return this;
    return WalletPalette(
      backgroundBase: Color.lerp(backgroundBase, other.backgroundBase, t)!,
      backgroundSurface: Color.lerp(
        backgroundSurface,
        other.backgroundSurface,
        t,
      )!,
      backgroundElevated: Color.lerp(
        backgroundElevated,
        other.backgroundElevated,
        t,
      )!,
      backgroundPanel: Color.lerp(backgroundPanel, other.backgroundPanel, t)!,
      backgroundOverlay: Color.lerp(
        backgroundOverlay,
        other.backgroundOverlay,
        t,
      )!,
      gradientAStart: Color.lerp(gradientAStart, other.gradientAStart, t)!,
      gradientAEnd: Color.lerp(gradientAEnd, other.gradientAEnd, t)!,
      gradientBStart: Color.lerp(gradientBStart, other.gradientBStart, t)!,
      gradientBEnd: Color.lerp(gradientBEnd, other.gradientBEnd, t)!,
      gradientCStart: Color.lerp(gradientCStart, other.gradientCStart, t)!,
      gradientCEnd: Color.lerp(gradientCEnd, other.gradientCEnd, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textOnAccent: Color.lerp(textOnAccent, other.textOnAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      successBackground: Color.lerp(
        successBackground,
        other.successBackground,
        t,
      )!,
      successBorder: Color.lerp(successBorder, other.successBorder, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBackground: Color.lerp(
        warningBackground,
        other.warningBackground,
        t,
      )!,
      warningBorder: Color.lerp(warningBorder, other.warningBorder, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorBackground: Color.lerp(errorBackground, other.errorBackground, t)!,
      errorBorder: Color.lerp(errorBorder, other.errorBorder, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoBackground: Color.lerp(infoBackground, other.infoBackground, t)!,
      infoBorder: Color.lerp(infoBorder, other.infoBorder, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      focusRingSubtle: Color.lerp(focusRingSubtle, other.focusRingSubtle, t)!,
      hoverOverlay: Color.lerp(hoverOverlay, other.hoverOverlay, t)!,
      pressedOverlay: Color.lerp(pressedOverlay, other.pressedOverlay, t)!,
      selectedBackground: Color.lerp(
        selectedBackground,
        other.selectedBackground,
        t,
      )!,
      selectedBorder: Color.lerp(selectedBorder, other.selectedBorder, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      shadowStrong: Color.lerp(shadowStrong, other.shadowStrong, t)!,
      qrBackground: Color.lerp(qrBackground, other.qrBackground, t)!,
      qrForeground: Color.lerp(qrForeground, other.qrForeground, t)!,
      chartColors: t < 0.5 ? chartColors : other.chartColors,
    );
  }
}
