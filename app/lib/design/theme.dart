import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens/colors.dart';
import 'themes/default_palette.dart';
import 'themes/wallet_palette.dart';
import 'tokens/spacing.dart';
import 'tokens/typography.dart';

const PageTransitionsTheme _piratePageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
  },
);

ScrollbarThemeData _pirateScrollbarTheme({
  required Color idleThumbColor,
  required Color hoveredThumbColor,
  required Color draggedThumbColor,
}) {
  return ScrollbarThemeData(
    thickness: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.dragged)) {
        return 6.0;
      }
      return 4.0;
    }),
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.dragged)) {
        return draggedThumbColor;
      }
      if (states.contains(WidgetState.hovered)) {
        return hoveredThumbColor;
      }
      return idleThumbColor;
    }),
    radius: const Radius.circular(PSpacing.radiusXS),
    crossAxisMargin: PSpacing.xxs,
    mainAxisMargin: PSpacing.xs,
    minThumbLength: 48.0,
  );
}

WidgetStateTextStyle _floatingInputLabelStyle({
  required Color idleColor,
  required Color focusedColor,
  required Color disabledColor,
  required Color errorColor,
}) {
  return WidgetStateTextStyle.resolveWith((states) {
    final color = states.contains(WidgetState.error)
        ? errorColor
        : states.contains(WidgetState.disabled)
        ? disabledColor
        : states.contains(WidgetState.focused)
        ? focusedColor
        : idleColor;
    return PTypography.labelMedium(color: color);
  });
}

/// Stashi Wallet theme system
///
/// Builds Material ThemeData from design tokens with dark-first approach
class PTheme {
  PTheme._();

  // ============================================================================
  // Main Theme Builders
  // ============================================================================

  /// Dark theme (default) - Premium dark UI
  static ThemeData dark({bool highContrast = false, WalletPalette? palette}) {
    final colors = palette ?? defaultDarkPalette;

    return ThemeData(
      useMaterial3: true,
      extensions: [colors],
      brightness: Brightness.dark,
      pageTransitionsTheme: _piratePageTransitions,

      // ========================================================================
      // Color Scheme
      // ========================================================================
      colorScheme: ColorScheme.dark(
        brightness: Brightness.dark,
        primary: colors.gradientAStart,
        onPrimary: colors.textOnAccent,
        primaryContainer: colors.backgroundElevated,
        onPrimaryContainer: colors.textPrimary,
        secondary: colors.gradientBStart,
        onSecondary: colors.textOnAccent,
        secondaryContainer: colors.backgroundSurface,
        onSecondaryContainer: colors.textPrimary,
        tertiary: colors.info,
        onTertiary: colors.textOnAccent,
        error: colors.error,
        onError: colors.textPrimary,
        errorContainer: colors.errorBackground,
        onErrorContainer: colors.error,
        surface: colors.backgroundSurface,
        onSurface: colors.textPrimary,
        surfaceContainerHighest: colors.backgroundElevated,
        onSurfaceVariant: colors.textSecondary,
        outline: highContrast
            ? PColorsHighContrast.borderDefault
            : colors.borderDefault,
        outlineVariant: colors.borderSubtle,
        shadow: colors.shadow,
        scrim: colors.backgroundOverlay,
        inverseSurface: colors.textPrimary,
        onInverseSurface: colors.backgroundBase,
        inversePrimary: colors.backgroundBase,
      ),

      scaffoldBackgroundColor: colors.backgroundBase,
      canvasColor: colors.backgroundBase,
      cardColor: colors.backgroundSurface,
      dividerColor: colors.divider,
      focusColor: colors.focusRingSubtle,
      hoverColor: colors.hoverOverlay,
      highlightColor: colors.pressedOverlay,
      splashColor: colors.pressedOverlay,
      disabledColor: colors.textDisabled,
      scrollbarTheme: _pirateScrollbarTheme(
        idleThumbColor:
            (highContrast
                    ? PColorsHighContrast.textSecondary
                    : colors.textDisabled)
                .withValues(alpha: highContrast ? 0.56 : 0.46),
        hoveredThumbColor:
            (highContrast
                    ? PColorsHighContrast.textSecondary
                    : colors.textDisabled)
                .withValues(alpha: highContrast ? 0.78 : 0.72),
        draggedThumbColor: highContrast
            ? PColorsHighContrast.textSecondary
            : colors.textDisabled,
      ),

      // ========================================================================
      // Typography
      // ========================================================================
      fontFamily: PTypography.fontFamilyUI,
      fontFamilyFallback: PTypography.fontFamilyFallback,

      textTheme: TextTheme(
        displayLarge: PTypography.displayLarge(color: colors.textPrimary),
        displayMedium: PTypography.displayMedium(color: colors.textPrimary),
        displaySmall: PTypography.displaySmall(color: colors.textPrimary),
        headlineLarge: PTypography.heading1(color: colors.textPrimary),
        headlineMedium: PTypography.heading2(color: colors.textPrimary),
        headlineSmall: PTypography.heading3(color: colors.textPrimary),
        titleLarge: PTypography.titleLarge(color: colors.textPrimary),
        titleMedium: PTypography.titleMedium(color: colors.textPrimary),
        titleSmall: PTypography.titleSmall(color: colors.textSecondary),
        bodyLarge: PTypography.bodyLarge(color: colors.textSecondary),
        bodyMedium: PTypography.bodyMedium(color: colors.textSecondary),
        bodySmall: PTypography.bodySmall(color: colors.textTertiary),
        labelLarge: PTypography.labelLarge(color: colors.textPrimary),
        labelMedium: PTypography.labelMedium(color: colors.textSecondary),
        labelSmall: PTypography.labelSmall(color: colors.textTertiary),
      ),

      // ========================================================================
      // AppBar Theme
      // ========================================================================
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: colors.backgroundBase,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: PTypography.heading5(color: colors.textPrimary),
        toolbarHeight: 64.0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: IconThemeData(
          color: colors.textPrimary,
          size: PSpacing.iconLG,
        ),
      ),

      // ========================================================================
      // Button Themes
      // ========================================================================
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: PSpacing.buttonPaddingHorizontal,
            vertical: PSpacing.buttonPaddingVertical,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PSpacing.radiusMD),
          ),
          textStyle: PTypography.labelLarge(),
          foregroundColor: colors.textOnAccent,
          backgroundColor: colors.gradientAStart,
          disabledForegroundColor: colors.textDisabled,
          disabledBackgroundColor: colors.backgroundSurface,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: PSpacing.buttonPaddingHorizontal,
            vertical: PSpacing.buttonPaddingVertical,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PSpacing.radiusMD),
          ),
          textStyle: PTypography.labelLarge(),
          foregroundColor: colors.textOnAccent,
          backgroundColor: colors.gradientAStart,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: PSpacing.buttonPaddingHorizontal,
            vertical: PSpacing.buttonPaddingVertical,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PSpacing.radiusMD),
          ),
          side: BorderSide(
            color: highContrast
                ? PColorsHighContrast.borderDefault
                : colors.borderDefault,
            width: 1.5,
          ),
          textStyle: PTypography.labelLarge(),
          foregroundColor: colors.textPrimary,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: PSpacing.md,
            vertical: PSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PSpacing.radiusSM),
          ),
          textStyle: PTypography.labelLarge(),
          foregroundColor: colors.gradientAStart,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.textPrimary,
          highlightColor: colors.hoverOverlay,
          padding: EdgeInsets.all(PSpacing.sm),
        ),
      ),

      // ========================================================================
      // Input Decoration Theme
      // ========================================================================
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.backgroundSurface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: PSpacing.inputPaddingHorizontal,
          vertical: PSpacing.inputPaddingVertical,
        ),

        // Border styles
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(color: colors.borderDefault, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(color: colors.borderDefault, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(
            color: highContrast
                ? PColorsHighContrast.focusRing
                : colors.focusRing,
            width: 2.0,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(color: colors.error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(color: colors.error, width: 2.0),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(color: colors.borderSubtle, width: 1.0),
        ),

        // Text styles
        labelStyle: PTypography.labelMedium(color: colors.textSecondary),
        floatingLabelStyle: _floatingInputLabelStyle(
          idleColor: highContrast
              ? PColorsHighContrast.textSecondary
              : colors.textSecondary,
          focusedColor: highContrast
              ? PColorsHighContrast.focusRing
              : colors.focusRing,
          disabledColor: colors.textDisabled,
          errorColor: colors.error,
        ),
        hintStyle: PTypography.bodyMedium(color: colors.textTertiary),
        errorStyle: PTypography.labelSmall(color: colors.error),
        helperStyle: PTypography.caption(color: colors.textTertiary),

        // Icons
        prefixIconColor: colors.textSecondary,
        suffixIconColor: colors.textSecondary,
      ),

      // ========================================================================
      // Card Theme
      // ========================================================================
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.backgroundSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusCard),
          side: BorderSide(color: colors.borderSubtle, width: 1.0),
        ),
        margin: EdgeInsets.all(PSpacing.sm),
      ),

      // ========================================================================
      // Dialog Theme
      // ========================================================================
      dialogTheme: DialogThemeData(
        elevation: 8,
        backgroundColor: colors.backgroundElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusXL),
        ),
        titleTextStyle: PTypography.heading4(color: colors.textPrimary),
        contentTextStyle: PTypography.bodyMedium(color: colors.textSecondary),
      ),

      // ========================================================================
      // Bottom Sheet Theme
      // ========================================================================
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        backgroundColor: colors.backgroundElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: colors.backgroundElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(PSpacing.radiusXL),
          ),
        ),
      ),

      // ========================================================================
      // List Tile Theme
      // ========================================================================
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: PSpacing.listItemPaddingHorizontal,
          vertical: PSpacing.listItemPaddingVertical,
        ),
        titleTextStyle: PTypography.titleSmall(color: colors.textPrimary),
        subtitleTextStyle: PTypography.bodySmall(color: colors.textSecondary),
        leadingAndTrailingTextStyle: PTypography.labelMedium(
          color: colors.textSecondary,
        ),
        iconColor: colors.textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusMD),
        ),
      ),

      // ========================================================================
      // Chip Theme
      // ========================================================================
      chipTheme: ChipThemeData(
        backgroundColor: colors.backgroundSurface,
        selectedColor: colors.selectedBackground,
        disabledColor: colors.backgroundSurface,
        labelStyle: PTypography.labelSmall(color: colors.textPrimary),
        secondaryLabelStyle: PTypography.labelSmall(
          color: colors.textSecondary,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: PSpacing.sm,
          vertical: PSpacing.xxs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusSM),
          side: BorderSide(color: colors.borderDefault, width: 1.0),
        ),
      ),

      // ========================================================================
      // Switch Theme
      // ========================================================================
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.textOnAccent;
          }
          return colors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.gradientAStart;
          }
          return colors.backgroundSurface;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return colors.borderDefault;
        }),
      ),

      // ========================================================================
      // Checkbox Theme
      // ========================================================================
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.gradientAStart;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(colors.textOnAccent),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(
              color: highContrast
                  ? PColorsHighContrast.focusRing
                  : colors.focusRing,
              width: 2,
            );
          }
          final color = states.contains(WidgetState.disabled)
              ? colors.textDisabled.withValues(alpha: 0.45)
              : highContrast
              ? PColorsHighContrast.borderDefault
              : colors.textSecondary.withValues(alpha: 0.72);
          return BorderSide(color: color, width: 1.5);
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusXS),
        ),
      ),

      // ========================================================================
      // Radio Theme
      // ========================================================================
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.gradientAStart;
          }
          return colors.borderDefault;
        }),
      ),

      // ========================================================================
      // Tooltip Theme
      // ========================================================================
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.backgroundElevated,
          borderRadius: BorderRadius.circular(PSpacing.radiusSM),
          border: Border.all(color: colors.borderDefault, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: colors.shadowStrong,
              blurRadius: 8.0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        textStyle: PTypography.labelSmall(color: colors.textPrimary),
        padding: EdgeInsets.all(PSpacing.tooltipPadding),
        waitDuration: Duration(milliseconds: 500),
      ),

      // ========================================================================
      // Snackbar Theme
      // ========================================================================
      snackBarTheme: SnackBarThemeData(
        elevation: 8,
        backgroundColor: colors.backgroundElevated,
        contentTextStyle: PTypography.bodyMedium(color: colors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusMD),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ========================================================================
      // Progress Indicator Theme
      // ========================================================================
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.gradientAStart,
        linearTrackColor: colors.backgroundSurface,
        circularTrackColor: colors.backgroundSurface,
      ),

      // ========================================================================
      // Divider Theme
      // ========================================================================
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1.0,
        space: 1.0,
      ),
    );
  }

  /// Light theme - Ivory
  static ThemeData light({WalletPalette? palette}) {
    final colors = palette ?? defaultLightPalette;
    return ThemeData(
      useMaterial3: true,
      extensions: [colors],
      brightness: Brightness.light,
      pageTransitionsTheme: _piratePageTransitions,

      // ========================================================================
      // Color Scheme
      // ========================================================================
      colorScheme: ColorScheme.light(
        brightness: Brightness.light,
        primary: colors.gradientAStart,
        onPrimary: colors.textOnAccent,
        primaryContainer: colors.backgroundElevated,
        onPrimaryContainer: colors.textPrimary,
        secondary: colors.gradientBStart,
        onSecondary: colors.textOnAccent,
        secondaryContainer: colors.backgroundSurface,
        onSecondaryContainer: colors.textPrimary,
        tertiary: colors.info,
        onTertiary: colors.textOnAccent,
        error: colors.error,
        onError: colors.textPrimary,
        errorContainer: colors.errorBackground,
        onErrorContainer: colors.error,
        surface: colors.backgroundSurface,
        onSurface: colors.textPrimary,
        surfaceContainerHighest: colors.backgroundElevated,
        onSurfaceVariant: colors.textSecondary,
        outline: colors.borderDefault,
        outlineVariant: colors.borderSubtle,
        shadow: colors.shadow,
        scrim: colors.backgroundOverlay,
        inverseSurface: colors.textPrimary,
        onInverseSurface: colors.backgroundBase,
        inversePrimary: colors.backgroundBase,
      ),

      scaffoldBackgroundColor: colors.backgroundBase,
      canvasColor: colors.backgroundBase,
      cardColor: colors.backgroundSurface,
      dividerColor: colors.divider,
      focusColor: colors.focusRingSubtle,
      hoverColor: colors.hoverOverlay,
      highlightColor: colors.pressedOverlay,
      splashColor: colors.pressedOverlay,
      disabledColor: colors.textDisabled,
      scrollbarTheme: _pirateScrollbarTheme(
        idleThumbColor: colors.textTertiary.withValues(alpha: 0.34),
        hoveredThumbColor: colors.textTertiary.withValues(alpha: 0.54),
        draggedThumbColor: colors.textTertiary.withValues(alpha: 0.76),
      ),

      // ========================================================================
      // Typography
      // ========================================================================
      fontFamily: PTypography.fontFamilyUI,
      fontFamilyFallback: PTypography.fontFamilyFallback,

      textTheme: TextTheme(
        displayLarge: PTypography.displayLarge(color: colors.textPrimary),
        displayMedium: PTypography.displayMedium(color: colors.textPrimary),
        displaySmall: PTypography.displaySmall(color: colors.textPrimary),
        headlineLarge: PTypography.heading1(color: colors.textPrimary),
        headlineMedium: PTypography.heading2(color: colors.textPrimary),
        headlineSmall: PTypography.heading3(color: colors.textPrimary),
        titleLarge: PTypography.titleLarge(color: colors.textPrimary),
        titleMedium: PTypography.titleMedium(color: colors.textPrimary),
        titleSmall: PTypography.titleSmall(color: colors.textSecondary),
        bodyLarge: PTypography.bodyLarge(color: colors.textSecondary),
        bodyMedium: PTypography.bodyMedium(color: colors.textSecondary),
        bodySmall: PTypography.bodySmall(color: colors.textTertiary),
        labelLarge: PTypography.labelLarge(color: colors.textPrimary),
        labelMedium: PTypography.labelMedium(color: colors.textSecondary),
        labelSmall: PTypography.labelSmall(color: colors.textTertiary),
      ),

      // ========================================================================
      // AppBar Theme
      // ========================================================================
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: colors.backgroundBase,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: PTypography.heading5(color: colors.textPrimary),
        toolbarHeight: 64.0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: IconThemeData(
          color: colors.textPrimary,
          size: PSpacing.iconLG,
        ),
      ),

      // ========================================================================
      // Button Themes
      // ========================================================================
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: PSpacing.buttonPaddingHorizontal,
            vertical: PSpacing.buttonPaddingVertical,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PSpacing.radiusMD),
          ),
          textStyle: PTypography.labelLarge(),
          foregroundColor: colors.textOnAccent,
          backgroundColor: colors.gradientAStart,
          disabledForegroundColor: colors.textDisabled,
          disabledBackgroundColor: colors.backgroundSurface,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: PSpacing.buttonPaddingHorizontal,
            vertical: PSpacing.buttonPaddingVertical,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PSpacing.radiusMD),
          ),
          textStyle: PTypography.labelLarge(),
          foregroundColor: colors.textOnAccent,
          backgroundColor: colors.gradientAStart,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: PSpacing.buttonPaddingHorizontal,
            vertical: PSpacing.buttonPaddingVertical,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PSpacing.radiusMD),
          ),
          side: BorderSide(color: colors.borderDefault, width: 1.5),
          textStyle: PTypography.labelLarge(),
          foregroundColor: colors.textPrimary,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: PSpacing.md,
            vertical: PSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PSpacing.radiusSM),
          ),
          textStyle: PTypography.labelLarge(),
          foregroundColor: colors.gradientAStart,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.textPrimary,
          highlightColor: colors.hoverOverlay,
          padding: EdgeInsets.all(PSpacing.sm),
        ),
      ),

      // ========================================================================
      // Input Decoration Theme
      // ========================================================================
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.backgroundSurface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: PSpacing.inputPaddingHorizontal,
          vertical: PSpacing.inputPaddingVertical,
        ),

        // Border styles
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(color: colors.borderDefault, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(color: colors.borderDefault, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(color: colors.focusRing, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(color: colors.error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(color: colors.error, width: 2.0),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusInput),
          borderSide: BorderSide(color: colors.borderSubtle, width: 1.0),
        ),

        // Text styles
        labelStyle: PTypography.labelMedium(color: colors.textSecondary),
        floatingLabelStyle: _floatingInputLabelStyle(
          idleColor: colors.textSecondary,
          focusedColor: colors.focusRing,
          disabledColor: colors.textDisabled,
          errorColor: colors.error,
        ),
        hintStyle: PTypography.bodyMedium(color: colors.textTertiary),
        errorStyle: PTypography.labelSmall(color: colors.error),
        helperStyle: PTypography.caption(color: colors.textTertiary),

        // Icons
        prefixIconColor: colors.textSecondary,
        suffixIconColor: colors.textSecondary,
      ),

      // ========================================================================
      // Card Theme
      // ========================================================================
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.backgroundSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusCard),
          side: BorderSide(color: colors.borderSubtle, width: 1.0),
        ),
        margin: EdgeInsets.all(PSpacing.sm),
      ),

      // ========================================================================
      // Dialog Theme
      // ========================================================================
      dialogTheme: DialogThemeData(
        elevation: 8,
        backgroundColor: colors.backgroundElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusXL),
        ),
        titleTextStyle: PTypography.heading4(color: colors.textPrimary),
        contentTextStyle: PTypography.bodyMedium(color: colors.textSecondary),
      ),

      // ========================================================================
      // Bottom Sheet Theme
      // ========================================================================
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        backgroundColor: colors.backgroundElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: colors.backgroundElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(PSpacing.radiusXL),
          ),
        ),
      ),

      // ========================================================================
      // List Tile Theme
      // ========================================================================
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: PSpacing.listItemPaddingHorizontal,
          vertical: PSpacing.listItemPaddingVertical,
        ),
        titleTextStyle: PTypography.titleSmall(color: colors.textPrimary),
        subtitleTextStyle: PTypography.bodySmall(color: colors.textSecondary),
        leadingAndTrailingTextStyle: PTypography.labelMedium(
          color: colors.textSecondary,
        ),
        iconColor: colors.textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusMD),
        ),
      ),

      // ========================================================================
      // Chip Theme
      // ========================================================================
      chipTheme: ChipThemeData(
        backgroundColor: colors.backgroundSurface,
        selectedColor: colors.selectedBackground,
        disabledColor: colors.backgroundSurface,
        labelStyle: PTypography.labelSmall(color: colors.textPrimary),
        secondaryLabelStyle: PTypography.labelSmall(
          color: colors.textSecondary,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: PSpacing.sm,
          vertical: PSpacing.xxs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusSM),
          side: BorderSide(color: colors.borderDefault, width: 1.0),
        ),
      ),

      // ========================================================================
      // Switch Theme
      // ========================================================================
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.textOnAccent;
          }
          return colors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.gradientAStart;
          }
          return colors.backgroundSurface;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return colors.borderDefault;
        }),
      ),

      // ========================================================================
      // Checkbox Theme
      // ========================================================================
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.gradientAStart;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(colors.textOnAccent),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: colors.focusRing, width: 2);
          }
          final color = states.contains(WidgetState.disabled)
              ? colors.textDisabled.withValues(alpha: 0.55)
              : colors.textSecondary.withValues(alpha: 0.68);
          return BorderSide(color: color, width: 1.5);
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusXS),
        ),
      ),

      // ========================================================================
      // Radio Theme
      // ========================================================================
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.gradientAStart;
          }
          return colors.borderDefault;
        }),
      ),

      // ========================================================================
      // Tooltip Theme
      // ========================================================================
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.backgroundElevated,
          borderRadius: BorderRadius.circular(PSpacing.radiusSM),
          border: Border.all(color: colors.borderDefault, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: colors.shadowStrong,
              blurRadius: 8.0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        textStyle: PTypography.labelSmall(color: colors.textPrimary),
        padding: EdgeInsets.all(PSpacing.tooltipPadding),
        waitDuration: Duration(milliseconds: 500),
      ),

      // ========================================================================
      // Snackbar Theme
      // ========================================================================
      snackBarTheme: SnackBarThemeData(
        elevation: 8,
        backgroundColor: colors.backgroundElevated,
        contentTextStyle: PTypography.bodyMedium(color: colors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PSpacing.radiusMD),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ========================================================================
      // Progress Indicator Theme
      // ========================================================================
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.gradientAStart,
        linearTrackColor: colors.backgroundSurface,
        circularTrackColor: colors.backgroundSurface,
      ),

      // ========================================================================
      // Divider Theme
      // ========================================================================
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1.0,
        space: 1.0,
      ),
    );
  }
}
