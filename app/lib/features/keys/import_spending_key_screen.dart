import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ffi/ffi_bridge.dart';
import '../../core/providers/wallet_providers.dart';
import '../../core/i18n/arb_text_localizer.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../../ui/atoms/p_button.dart';
import '../../ui/atoms/p_input.dart';
import '../../ui/molecules/p_card.dart';
import '../../ui/organisms/p_app_bar.dart';
import '../../ui/organisms/p_scaffold.dart';
import 'spending_key_input.dart';

final spendingKeyImporterProvider = Provider(
  (ref) => FfiBridge.importSpendingKey,
);
final importedKeyRescanProvider = Provider((ref) => FfiBridge.rescan);

class ImportSpendingKeyScreen extends ConsumerStatefulWidget {
  const ImportSpendingKeyScreen({super.key});

  @override
  ConsumerState<ImportSpendingKeyScreen> createState() =>
      _ImportSpendingKeyScreenState();
}

class _ImportSpendingKeyScreenState
    extends ConsumerState<ImportSpendingKeyScreen> {
  final _labelController = TextEditingController();
  final _birthdayController = TextEditingController();
  final _keyController = TextEditingController();
  final _keyFocus = FocusNode();
  final _birthdayFocus = FocusNode();
  bool _isSubmitting = false;
  bool _revealKey = false;
  String? _keyError;
  String? _birthdayError;
  String? _error;
  ({String walletId, int keyId, int birthday})? _imported;

  @override
  void dispose() {
    _labelController.dispose();
    _birthdayController.dispose();
    _keyController.dispose();
    _keyFocus.dispose();
    _birthdayFocus.dispose();
    super.dispose();
  }

  String _inputError(SpendingKeyInputError error) => switch (error) {
    SpendingKeyInputError.empty => 'Enter a spending key to continue.'.tr,
    SpendingKeyInputError.format =>
      'Use a Sapling or Ironwood spending key, not an address or viewing key.'
          .tr,
    SpendingKeyInputError.duplicate =>
      'Enter only one key of each type. Import other keys separately.'.tr,
    SpendingKeyInputError.tooMany =>
      'Enter one spending key, or one Sapling and one Ironwood key.'.tr,
  };

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final walletId = _imported?.walletId ?? ref.read(activeWalletProvider);
    if (walletId == null) {
      setState(() => _error = 'No active wallet'.tr);
      return;
    }

    SpendingKeyInput? keys;
    final birthday =
        _imported?.birthday ?? int.tryParse(_birthdayController.text.trim());
    if (_imported == null) {
      String? keyError;
      try {
        keys = SpendingKeyInput.parse(_keyController.text);
      } on SpendingKeyInputException catch (error) {
        keyError = _inputError(error.reason);
      }
      final birthdayError =
          birthday == null || birthday <= 0 || birthday > 0xffffffff
          ? 'Enter a valid birthday height'.tr
          : null;
      setState(() {
        _keyError = keyError;
        _birthdayError = birthdayError;
        _error = null;
      });
      if (keyError != null || birthdayError != null) {
        (keyError != null ? _keyFocus : _birthdayFocus).requestFocus();
        return;
      }
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    // Capture callbacks before awaiting; scan the wallet that received the key,
    // even if the active wallet changes during the import.
    final importer = ref.read(spendingKeyImporterProvider);
    final rescan = ref.read(importedKeyRescanProvider);
    try {
      if (_imported == null) {
        final label = _labelController.text.trim();
        final keyId = await importer(
          walletId: walletId,
          saplingKey: keys!.sapling,
          ironwoodKey: keys.ironwood,
          label: label.isEmpty ? null : label,
          birthdayHeight: birthday!,
        );
        if (!mounted) return;
        _imported = (walletId: walletId, keyId: keyId, birthday: birthday);
        _keyController.clear();
        _revealKey = false;
        ref.read(refreshWalletRuntimeProvider)();
      }
      final imported = _imported!;
      await rescan(imported.walletId, imported.birthday);
      if (!mounted) return;
      ref.read(refreshWalletRuntimeProvider)();
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rescan started from block {height}'.trArgs({
              'height': imported.birthday,
            }),
          ),
        ),
      );
      if (ref.read(activeWalletProvider) == imported.walletId) {
        context.pushReplacement(
          '/settings/keys/detail?keyId=${imported.keyId}',
        );
      } else {
        context.pop();
      }
    } catch (error) {
      if (!mounted) return;
      // Raw errors can contain native diagnostics. Never echo private input.
      final message = error.toString();
      final wrongNetwork =
          message.contains('does not match wallet network') ||
          message.contains('different networks');
      final invalidKey =
          message.contains('Invalid Sapling spending key') ||
          message.contains('Invalid Ironwood spending key');
      setState(() {
        _error = _imported != null
            ? 'Your key is imported. Scanning could not start. Retry scanning without importing again.'
                  .tr
            : wrongNetwork
            ? 'This key belongs to a different network than the current wallet.'
                  .tr
            : invalidKey
            ? 'The spending key could not be validated. Check that you copied the entire key.'
                  .tr
            : 'Could not import the key. Unlock your wallet and try again.'.tr;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = !_isSubmitting && _imported == null;
    return PopScope(
      canPop: !_isSubmitting,
      child: PScaffold(
        bodyMaxWidth: 760,
        appBar: PAppBar(
          title: 'Import spending key'.tr,
          subtitle: 'Add an existing key to this wallet'.tr,
          showBackButton: true,
        ),
        body: SingleChildScrollView(
          padding: PSpacing.screenPadding(MediaQuery.sizeOf(context).width),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(PSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.selectedBackground,
                          borderRadius: BorderRadius.circular(
                            PSpacing.radiusMD,
                          ),
                        ),
                        child: Icon(
                          Icons.key_outlined,
                          color: AppColors.accentPrimary,
                        ),
                      ),
                      const SizedBox(width: PSpacing.sm),
                      Expanded(
                        child: Text(
                          'Add a private key'.tr,
                          style: PTypography.heading4(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: PSpacing.sm),
                  Text(
                    'Import a Sapling or Ironwood spending key. The format is detected automatically.'
                        .tr,
                    style: PTypography.bodyMedium(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: PSpacing.lg),
                  PCard(
                    padding: const EdgeInsets.all(PSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PInput(
                          controller: _keyController,
                          focusNode: _keyFocus,
                          label: 'Spending key'.tr,
                          hint: _imported == null
                              ? 'Paste your spending key'.tr
                              : 'Key imported'.tr,
                          sensitive: true,
                          obscureText: !_revealKey,
                          enabled: editable,
                          monospace: true,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.next,
                          errorText: _keyError,
                          onChanged: (_) {
                            if (_keyError != null || _error != null) {
                              setState(() {
                                _keyError = null;
                                _error = null;
                              });
                            }
                          },
                          onSubmitted: (_) => _birthdayFocus.requestFocus(),
                          suffixIcon: IconButton(
                            tooltip: _revealKey ? 'Hide key'.tr : 'Show key'.tr,
                            onPressed: editable
                                ? () => setState(() => _revealKey = !_revealKey)
                                : null,
                            icon: Icon(
                              _revealKey
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(height: PSpacing.lg),
                        PInput(
                          controller: _birthdayController,
                          focusNode: _birthdayFocus,
                          label: 'Birthday height'.tr,
                          hint: 'Block height to start scanning'.tr,
                          helperText: 'Use a height from before the key first received funds. An earlier height takes longer to scan.'
                              .tr,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          enabled: editable,
                          errorText: _birthdayError,
                          onChanged: (_) {
                            if (_birthdayError != null) {
                              setState(() => _birthdayError = null);
                            }
                          },
                        ),
                        const SizedBox(height: PSpacing.lg),
                        PInput(
                          controller: _labelController,
                          label: 'Label (optional)'.tr,
                          hint: 'Example: Legacy wallet'.tr,
                          enabled: editable,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.manage_search,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: PSpacing.xs),
                      Expanded(
                        child: Text(
                          'A rescan will start automatically from the birthday height.'
                              .tr,
                          style: PTypography.bodySmall(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: PSpacing.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: PTypography.bodySmall(color: AppColors.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: PSpacing.lg),
                  PButton(
                    onPressed: _isSubmitting ? null : _submit,
                    loading: _isSubmitting,
                    fullWidth: true,
                    text: _imported != null
                        ? 'Retry scanning'.tr
                        : 'Import and scan'.tr,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
