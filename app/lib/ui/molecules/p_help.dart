import 'package:flutter/material.dart';

import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../../core/i18n/arb_text_localizer.dart';

/// Supplemental help reachable by hover, long press, tap, and keyboard.
/// Keep information required to authorize a payment visible in the page itself.
class PHelpButton extends StatefulWidget {
  const PHelpButton({required this.message, required this.topic, super.key});

  final String message;
  final String topic;

  @override
  State<PHelpButton> createState() => _PHelpButtonState();
}

class _PHelpButtonState extends State<PHelpButton> {
  final _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      key: _tooltipKey,
      message: widget.message,
      excludeFromSemantics: true,
      triggerMode: TooltipTriggerMode.longPress,
      waitDuration: const Duration(milliseconds: 400),
      showDuration: const Duration(seconds: 8),
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(PSpacing.md),
      margin: const EdgeInsets.all(PSpacing.md),
      textStyle: PTypography.bodySmall(color: AppColors.textPrimary),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: BorderRadius.circular(PSpacing.radiusMD),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 16)],
      ),
      child: Semantics(
        label: 'About {topic}'.trArgs({'topic': widget.topic}),
        hint: widget.message,
        child: IconButton(
          onPressed: () => _tooltipKey.currentState?.ensureTooltipVisible(),
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          color: AppColors.textSecondary,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        ),
      ),
    );
  }
}

class PHelpLabel extends StatelessWidget {
  const PHelpLabel({required this.label, required this.help, super.key});

  final String label;
  final String help;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: Text(
          label,
          style: PTypography.bodyMedium(color: AppColors.textPrimary),
        ),
      ),
      PHelpButton(message: help, topic: label),
    ],
  );
}
