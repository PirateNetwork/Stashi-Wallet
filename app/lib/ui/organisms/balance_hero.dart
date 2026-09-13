import 'package:flutter/material.dart';

import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../atoms/p_icon_button.dart';
import '../../core/i18n/arb_text_localizer.dart';

class BalanceHero extends StatelessWidget {
  static const String _maskedBalanceText = '*******';

  const BalanceHero({
    required this.balanceText,
    this.label = 'Balance',
    this.secondaryText,
    this.helperText,
    this.compact = false,
    this.isHidden = false,
    this.onToggleVisibility,
    this.onSwapDisplay,
    super.key,
  });

  final String balanceText;
  final String label;
  final String? secondaryText;
  final String? helperText;
  final bool compact;
  final bool isHidden;
  final VoidCallback? onToggleVisibility;
  final VoidCallback? onSwapDisplay;

  @override
  Widget build(BuildContext context) {
    final displayText = isHidden ? _maskedBalanceText : balanceText;
    final displaySecondaryText = secondaryText == null
        ? null
        : (isHidden ? _maskedBalanceText : secondaryText!);
    final cardPadding = compact ? PSpacing.sm : PSpacing.lg;
    final titleStyle = compact
        ? PTypography.heading4(color: AppColors.of(context).textPrimary)
        : PTypography.displaySmall(color: AppColors.of(context).textPrimary);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.of(context).backgroundSurface,
        borderRadius: BorderRadius.circular(PSpacing.radiusCard),
        border: Border.all(color: AppColors.of(context).borderStrong),
        gradient: LinearGradient(
          colors: [
            AppColors.of(context).gradientAStart.withValues(alpha: 0.08),
            AppColors.of(context).gradientBStart.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.of(context).shadow,
            blurRadius: compact ? 8 : 12,
            offset: Offset(0, compact ? 4 : 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                label,
                style: PTypography.labelLarge(
                  color: AppColors.of(context).textSecondary,
                ),
              ),
              const Spacer(),
              if (onToggleVisibility != null)
                PIconButton(
                  icon: Icon(
                    isHidden ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.of(context).textSecondary,
                  ),
                  onPressed: onToggleVisibility,
                  tooltip: isHidden ? 'Show balance'.tr : 'Hide balance'.tr,
                  size: compact
                      ? PIconButtonSize.medium
                      : PIconButtonSize.large,
                ),
            ],
          ),
          SizedBox(height: compact ? PSpacing.xxs : PSpacing.sm),
          // Replace values immediately: cross-fading retains the unmasked
          // balance in both the render and semantics trees while hiding it.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              displayText,
              style: titleStyle.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (displaySecondaryText != null) ...[
            SizedBox(height: compact ? PSpacing.xxs : PSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    displaySecondaryText,
                    style: PTypography.labelSmall(
                      color: AppColors.of(context).textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onSwapDisplay != null)
                  PIconButton(
                    icon: Icon(
                      Icons.swap_vert,
                      color: AppColors.of(context).textSecondary,
                    ),
                    onPressed: onSwapDisplay,
                    tooltip: 'Swap balance display'.tr,
                    size: compact
                        ? PIconButtonSize.medium
                        : PIconButtonSize.large,
                  ),
              ],
            ),
          ],
          if (helperText != null && !isHidden) ...[
            SizedBox(height: compact ? PSpacing.xxs : PSpacing.sm),
            Text(
              helperText!,
              style: PTypography.bodySmall(
                color: AppColors.of(context).textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
