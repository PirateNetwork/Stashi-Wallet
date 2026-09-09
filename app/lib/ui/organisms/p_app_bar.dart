import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/platform_utils.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../atoms/p_icon_button.dart';
import '../atoms/theme_toggle_button.dart';
import '../../core/i18n/arb_text_localizer.dart';

/// Premium app bar replacement with Pirate design language.
class PAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PAppBar({
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.showBackButton,
    this.onBack,
    this.useGradientBackground = false,
    this.centerTitle = false,
    this.surfaceColor,
    this.showThemeToggle = false,
    this.preserveLayout = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool? showBackButton;
  final VoidCallback? onBack;
  final bool useGradientBackground;
  final bool centerTitle;
  final Color? surfaceColor;
  final bool showThemeToggle;

  /// Preserve the approved dashboard/action-hub presentation.
  final bool preserveLayout;

  @override
  Size get preferredSize => Size.fromHeight(preserveLayout ? 82 : 72);

  double preferredHeightFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (!preserveLayout) {
      final scaled = MediaQuery.textScalerOf(context).scale(1);
      if (scaled > 1.3) return (54 * scaled + 16).clamp(88, 160);
      return PSpacing.isCompactLandscape(size) ? 64 : 72;
    }
    if (PSpacing.isCompactLandscape(size)) return 64;
    if (isDesktopPlatform && PSpacing.isCompactDesktopViewport(size)) {
      return 68;
    }
    return 82;
  }

  bool _shouldShowBack(BuildContext context) {
    if (showBackButton != null) {
      return showBackButton!;
    }
    if (onBack != null) return true;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) {
      return false;
    }
    return navigator.canPop();
  }

  bool _isOnboardingRoute(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      return false;
    }
    try {
      final location = GoRouterState.of(context).uri.path;
      return location.startsWith('/onboarding');
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = MediaQuery.of(context).padding.top;
    final isNarrow = mediaQuery.size.width < 360;
    final isMobile = PSpacing.isHandset(mediaQuery.size);
    final compactLandscape = PSpacing.isCompactLandscape(mediaQuery.size);
    final compactDesktop =
        isDesktopPlatform && PSpacing.isCompactDesktopViewport(mediaQuery.size);
    final compactViewport = compactLandscape || compactDesktop;
    final textScale = mediaQuery.textScaler.scale(1);
    final verticalPadding = !preserveLayout
        ? PSpacing.xs
        : compactViewport
        ? PSpacing.xs
        : isMobile
        ? PSpacing.sm
        : PSpacing.md;
    final horizontalPadding = isMobile || compactDesktop
        ? PSpacing.md
        : PSpacing.lg;
    final resolvedLeading =
        leading ??
        (_shouldShowBack(context) ? _buildBackButton(context) : null);

    // Automatically add theme toggle to actions if not in onboarding
    final effectiveActions = <Widget>[];
    if (actions != null) {
      effectiveActions.addAll(actions!);
    }
    if (showThemeToggle && !_isOnboardingRoute(context)) {
      effectiveActions.add(const ThemeToggleButton());
    }

    final gradient = useGradientBackground
        ? LinearGradient(
            colors: [
              AppColors.gradientAStart.withValues(alpha: 0.35),
              AppColors.gradientAEnd.withValues(alpha: 0.2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : null;

    final decoration = BoxDecoration(
      color: gradient == null
          ? (surfaceColor ??
                (preserveLayout
                    ? AppColors.backgroundSurface
                    : AppColors.backgroundBase))
          : null,
      gradient: gradient,
      border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      boxShadow: preserveLayout
          ? [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ]
          : null,
    );

    final titleStyle = PTypography.titleMedium(color: AppColors.textPrimary)
        .copyWith(
          fontSize: preserveLayout
              ? (isMobile ? 16 : (isNarrow ? 15 : 17))
              : 18,
          fontWeight: FontWeight.w600,
          height: preserveLayout ? 1.5 : 1.2,
        );
    final subtitleStyle = PTypography.caption(color: AppColors.textSecondary)
        .copyWith(fontSize: isMobile ? 10 : 11);
    final showSubtitle =
        preserveLayout &&
        subtitle != null &&
        textScale <= 1.3 &&
        !compactLandscape;

    final titleColumn = Column(
      crossAxisAlignment: centerTitle
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: titleStyle,
          textAlign: centerTitle ? TextAlign.center : TextAlign.left,
          maxLines: preserveLayout ? 1 : 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (showSubtitle) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: subtitleStyle,
            textAlign: centerTitle ? TextAlign.center : TextAlign.left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    final trailing = effectiveActions.isNotEmpty
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: effectiveActions
                .map(
                  (action) => Padding(
                    padding: EdgeInsets.only(
                      left: compactViewport ? PSpacing.xs : PSpacing.sm,
                    ),
                    child: action,
                  ),
                )
                .toList(),
          )
        : null;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: decoration,
        padding: EdgeInsets.only(
          top: topPadding + verticalPadding,
          bottom: verticalPadding,
          left: horizontalPadding,
          right: horizontalPadding,
        ),
        child: NavigationToolbar(
          leading: resolvedLeading,
          middle: titleColumn,
          trailing: trailing,
          centerMiddle: centerTitle,
          middleSpacing: centerTitle ? PSpacing.sm : PSpacing.md,
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return SizedBox(
      width: PIconButtonSize.medium.size,
      child: Align(
        alignment: Alignment.centerLeft,
        child: PIconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          tooltip: 'Back'.tr,
          size: PIconButtonSize.medium,
          shape: PIconButtonShape.circle,
        ),
      ),
    );
  }
}
