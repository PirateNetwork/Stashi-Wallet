import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../ui/molecules/p_card.dart';
import '../../../ui/atoms/p_button.dart';
import '../../../core/i18n/arb_text_localizer.dart';

/// Widget displaying address as QR code
class AddressQRWidget extends StatelessWidget {
  final String address;
  final String? qrData;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final String? copyTooltip;
  final String? shareTooltip;

  const AddressQRWidget({
    super.key,
    required this.address,
    required this.onCopy,
    required this.onShare,
    this.qrData,
    this.copyTooltip,
    this.shareTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return PCard(
      padding: const EdgeInsets.all(PSpacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              // QR Code
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 272),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    padding: EdgeInsets.all(PSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.qrBackground,
                      borderRadius: BorderRadius.circular(PSpacing.radiusCard),
                    ),
                    child: QrImageView(
                      data: qrData ?? address,
                      version: QrVersions.auto,
                      size: 240,
                      backgroundColor: AppColors.qrBackground,
                      padding: EdgeInsets.all(PSpacing.sm),
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                    ),
                  ),
                ),
              ),

              SizedBox(height: PSpacing.lg),

              // Address Display
              Container(
                padding: EdgeInsets.all(PSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPanel,
                  borderRadius: BorderRadius.circular(PSpacing.radiusInput),
                  border: Border.all(color: AppColors.borderSubtle, width: 1),
                ),
                child: SelectableText(
                  address,
                  style: PTypography.codeMedium().copyWith(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              SizedBox(height: PSpacing.md),

              // Quick Actions
              LayoutBuilder(
                builder: (context, constraints) {
                  final copy = Tooltip(
                    message: copyTooltip ?? 'Copy address'.tr,
                    child: PButton(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy, size: 20),
                      text: 'Copy'.tr,
                      fullWidth: true,
                    ),
                  );
                  final share = Tooltip(
                    message: shareTooltip ?? 'Share address'.tr,
                    child: PButton(
                      onPressed: onShare,
                      icon: const Icon(Icons.share, size: 20),
                      text: 'Share'.tr,
                      fullWidth: true,
                      variant: PButtonVariant.outline,
                    ),
                  );
                  if (constraints.maxWidth < 300 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                    return Column(
                      children: [
                        copy,
                        const SizedBox(height: PSpacing.sm),
                        share,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: copy),
                      const SizedBox(width: PSpacing.sm),
                      Expanded(child: share),
                    ],
                  );
                },
              ),

              SizedBox(height: PSpacing.sm),

              // Address Type Badge
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: PSpacing.md,
                  vertical: PSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.selectedBackground,
                  borderRadius: BorderRadius.circular(PSpacing.radiusFull),
                  border: Border.all(color: AppColors.selectedBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outlined,
                      size: 14,
                      color: AppColors.focusRing,
                    ),
                    SizedBox(width: PSpacing.xs),
                    Flexible(
                      child: Text(
                        'Shielded address'.tr,
                        style: PTypography.labelSmall().copyWith(
                          color: AppColors.focusRing,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
