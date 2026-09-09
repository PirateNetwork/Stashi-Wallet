import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/arb_text_localizer.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../atoms/p_input.dart';
import 'p_help.dart';

/// The same supported viewing-key formats in setup and wallet management.
class ViewingKeyFields extends StatefulWidget {
  const ViewingKeyFields({
    required this.saplingController,
    required this.ironwoodController,
    super.key,
  });

  final TextEditingController saplingController;
  final TextEditingController ironwoodController;

  @override
  State<ViewingKeyFields> createState() => _ViewingKeyFieldsState();
}

class _ViewingKeyFieldsState extends State<ViewingKeyFields> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.ironwoodController.text.isNotEmpty
          ? widget.ironwoodController.text
          : widget.saplingController.text,
    )..addListener(_detectPool);
  }

  void _detectPool() {
    final text = _controller.text.trim();
    final isIronwood = text.startsWith('pirate-extended-viewing-key1');
    // Unknown formats still reach the native validator; never discard input.
    widget.saplingController.text = isIronwood ? '' : text;
    widget.ironwoodController.text = isIronwood ? text : '';
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PHelpLabel(
        label: 'Viewing key'.tr,
        help: 'Sapling: zxviews1…\nIronwood: pirate-extended-viewing-key1…',
      ),
      const SizedBox(height: PSpacing.xs),
      _field(
        context,
        _controller,
        'Enter a Sapling or Ironwood viewing key'.tr,
      ),
    ],
  );

  Widget _field(
    BuildContext context,
    TextEditingController controller,
    String hint,
  ) => PInput(
    controller: controller,
    hint: hint,
    sensitive: true,
    maxLines: 3,
    suffixIcon: IconButton(
      tooltip: 'Paste from clipboard'.tr,
      icon: const Icon(Icons.content_paste),
      color: AppColors.textSecondary,
      onPressed: () async {
        final value = await Clipboard.getData(Clipboard.kTextPlain);
        if (context.mounted && value?.text != null) {
          controller.text = value!.text!.trim();
        }
      },
    ),
  );
}
