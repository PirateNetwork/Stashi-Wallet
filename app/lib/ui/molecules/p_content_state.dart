import 'package:flutter/material.dart';

import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../atoms/p_button.dart';

/// A readable status with a concrete next action for empty or failed content.
/// Place inside a scrollable so enlarged text and short windows remain usable.
class PContentState extends StatelessWidget {
  const PContentState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: PSpacing.lg,
            horizontal: PSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(PSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.selectedBackground,
                  shape: BoxShape.circle,
                ),
                child: loading
                    ? SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: title,
                        ),
                      )
                    : Icon(icon, size: 28, color: AppColors.accentPrimary),
              ),
              const SizedBox(height: PSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: PTypography.heading4(color: AppColors.textPrimary),
              ),
              const SizedBox(height: PSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: PTypography.bodyMedium(color: AppColors.textSecondary),
              ),
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(height: PSpacing.lg),
                PButton(
                  onPressed: onAction,
                  text: actionLabel,
                  variant: PButtonVariant.secondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
