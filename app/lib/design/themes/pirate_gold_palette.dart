import 'package:flutter/material.dart';

import '../tokens/default_colors.dart';
import 'wallet_palette.dart';

/// Pirate Gold wallet style.
///
/// Keeps the semantic structure of Stashi's default palette while replacing
/// the visual identity with warm gold, bronze, treasure-brown and parchment
/// tones. Both light and dark variants are provided.
const pirateGoldDarkPalette = WalletPalette(
  // Backgrounds
  backgroundBase: Color(0xFF0D0A07),
  backgroundSurface: Color(0xFF16110C),
  backgroundElevated: Color(0xFF21180F),
  backgroundPanel: Color(0xFF302116),
  backgroundOverlay: Color(0xCC080503),

  // Accent gradients
  gradientAStart: Color(0xFFE8B84A),
  gradientAEnd: Color(0xFFC18B38),
  gradientBStart: Color(0xFFD59A36),
  gradientBEnd: Color(0xFFBD8B49),
  gradientCStart: Color(0xFFF3D27A),
  gradientCEnd: Color(0xFFC18B38),
  highlight: Color(0xFFFFD56A),

  // Text
  textPrimary: Color(0xFFFFF6DE),
  textSecondary: Color(0xFFE7D4AE),
  textTertiary: Color(0xFFBCA57E),
  textDisabled: Color(0xFF806F59),
  textOnAccent: Color(0xFF211507),

  // Semantic states
  success: PColors.success,
  successBackground: PColors.successBackground,
  successBorder: PColors.successBorder,
  warning: PColors.warning,
  warningBackground: PColors.warningBackground,
  warningBorder: PColors.warningBorder,
  error: PColors.error,
  errorBackground: PColors.errorBackground,
  errorBorder: PColors.errorBorder,
  info: PColors.info,
  infoBackground: PColors.infoBackground,
  infoBorder: PColors.infoBorder,

  // Interaction
  focusRing: Color(0xFFE8B84A),
  focusRingSubtle: Color(0x40E8B84A),
  hoverOverlay: Color(0x12FFD56A),
  pressedOverlay: Color(0x24FFD56A),
  selectedBackground: Color(0x26E8B84A),
  selectedBorder: Color(0x99E8B84A),

  // Borders
  borderDefault: Color(0x33D9A441),
  borderSubtle: Color(0x1FD9A441),
  borderStrong: Color(0x66E8B84A),
  divider: Color(0x2BD9A441),

  // Shadows
  shadow: Color(0x52000000),
  shadowStrong: Color(0x80000000),

  // QR codes remain maximum-contrast for reliable scanning.
  qrBackground: Color(0xFFFFFFFF),
  qrForeground: Color(0xFF000000),

  // Charts
  chartColors: [
    Color(0xFFE8B84A),
    Color(0xFFC18B38),
    Color(0xFFD59A36),
    Color(0xFF6E9FD8),
    Color(0xFF3DBB74),
    Color(0xFFE45B55),
  ],
);

const pirateGoldLightPalette = WalletPalette(
  // Warm parchment / sand backgrounds
  backgroundBase: Color(0xFFF7F0DE),
  backgroundSurface: Color(0xFFFFFBF2),
  backgroundElevated: Color(0xFFF0E2C4),
  backgroundPanel: Color(0xFFE7D3AA),
  backgroundOverlay: Color(0x990D0904),

  // Accent gradients
  gradientAStart: Color(0xFF946014),
  gradientAEnd: Color(0xFF8E5A18),
  gradientBStart: Color(0xFF916513),
  gradientBEnd: Color(0xFF945C1A),
  gradientCStart: Color(0xFF95651D),
  gradientCEnd: Color(0xFF9A5F1D),
  highlight: Color(0xFFD99A28),

  // Text
  textPrimary: Color(0xFF261A0D),
  textSecondary: Color(0xFF4D3821),
  textTertiary: Color(0xFF765E3E),
  textDisabled: Color(0xFF9C896D),
  textOnAccent: Color(0xFFFFFFFF),

  // Semantic states
  success: PColorsLight.success,
  successBackground: PColorsLight.successBackground,
  successBorder: PColorsLight.successBorder,
  warning: PColorsLight.warning,
  warningBackground: PColorsLight.warningBackground,
  warningBorder: PColorsLight.warningBorder,
  error: PColorsLight.error,
  errorBackground: PColorsLight.errorBackground,
  errorBorder: PColorsLight.errorBorder,
  info: PColorsLight.info,
  infoBackground: PColorsLight.infoBackground,
  infoBorder: PColorsLight.infoBorder,

  // Interaction
  focusRing: Color(0xFF946014),
  focusRingSubtle: Color(0x40C88A25),
  hoverOverlay: Color(0x0D8E5A18),
  pressedOverlay: Color(0x1A8E5A18),
  selectedBackground: Color(0x1FC88A25),
  selectedBorder: Color(0x80C88A25),

  // Borders
  borderDefault: Color(0x26724A1F),
  borderSubtle: Color(0x14724A1F),
  borderStrong: Color(0x4D8E5A18),
  divider: Color(0x26724A1F),

  // Shadows
  shadow: Color(0x26000000),
  shadowStrong: Color(0x40000000),

  // QR codes remain maximum-contrast for reliable scanning.
  qrBackground: Color(0xFFFFFFFF),
  qrForeground: Color(0xFF000000),

  // Charts
  chartColors: [
    Color(0xFF946014),
    Color(0xFF8E5A18),
    Color(0xFF916513),
    Color(0xFF376FA6),
    Color(0xFF238653),
    Color(0xFFC8433E),
  ],
);
