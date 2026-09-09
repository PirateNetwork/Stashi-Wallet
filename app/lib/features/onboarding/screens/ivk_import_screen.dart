// Viewing key import screen - create watch-only wallet from a viewing key

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/deep_space_theme.dart';
import '../../../ui/atoms/p_button.dart';
import '../../../ui/atoms/p_input.dart';
import '../../../ui/molecules/viewing_key_fields.dart';
import '../../../ui/organisms/p_app_bar.dart';
import '../../../ui/organisms/p_scaffold.dart';
import '../../../core/ffi/ffi_bridge.dart';
import '../../../core/providers/wallet_providers.dart';
import '../../../core/i18n/arb_text_localizer.dart';
import '../onboarding_flow.dart';
import '../onboarding_security.dart';

/// Viewing key import screen for creating watch-only wallets
class ViewingKeysImportScreen extends ConsumerStatefulWidget {
  const ViewingKeysImportScreen({
    super.key,
    this.securityServices = const OnboardingSecurityServices(),
  });

  final OnboardingSecurityServices securityServices;

  @override
  ConsumerState<ViewingKeysImportScreen> createState() =>
      _ViewingKeysImportScreenState();
}

class _ViewingKeysImportScreenState
    extends ConsumerState<ViewingKeysImportScreen> {
  final _nameController = TextEditingController(text: 'View only wallet'.tr);
  final _saplingIvkController = TextEditingController();
  final _ironwoodIvkController = TextEditingController();
  final _birthdayController = TextEditingController();

  bool _isImporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDefaultBirthday());
    _nameController.addListener(_onFieldChanged);
    _saplingIvkController.addListener(_onFieldChanged);
    _ironwoodIvkController.addListener(_onFieldChanged);
    _birthdayController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFieldChanged);
    _saplingIvkController.removeListener(_onFieldChanged);
    _ironwoodIvkController.removeListener(_onFieldChanged);
    _birthdayController.removeListener(_onFieldChanged);
    _nameController.dispose();
    _saplingIvkController.dispose();
    _ironwoodIvkController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  bool get _isValid {
    final hasKey =
        _saplingIvkController.text.trim().isNotEmpty ||
        _ironwoodIvkController.text.trim().isNotEmpty;
    return _nameController.text.trim().isNotEmpty &&
        hasKey &&
        _birthdayController.text.trim().isNotEmpty;
  }

  void _onFieldChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadDefaultBirthday() async {
    try {
      final defaultBirthday = await FfiBridge.getDefaultBirthdayHeight();
      if (!mounted) return;
      if (_birthdayController.text.trim().isEmpty) {
        _birthdayController.text = defaultBirthday.toString();
      }
    } catch (_) {}
  }

  Future<void> _importViewingKeys() async {
    if (!_isValid) return;

    setState(() {
      _isImporting = true;
      _error = null;
    });

    try {
      final onboardingState = ref.read(onboardingControllerProvider);
      final hasPassphrase = await widget.securityServices.hasAppPassphrase();
      final appUnlocked = ref.read(appUnlockedProvider);
      final setupPassphrase = onboardingState.passphrase;
      final securityRequirement = resolveWalletSetupSecurity(
        hasAppPassphrase: hasPassphrase,
        appUnlocked: appUnlocked,
        passphraseEstablishedInFlow: setupPassphrase?.isNotEmpty ?? false,
      );
      if (securityRequirement != WalletSetupSecurityRequirement.ready) {
        if (!mounted) return;
        if (securityRequirement ==
            WalletSetupSecurityRequirement.createPassphrase) {
          ref.read(onboardingControllerProvider.notifier)
            ..reset(startAt: OnboardingStep.createOrImport)
            ..setMode(OnboardingMode.watchOnly)
            ..nextStep();
          setState(() => _isImporting = false);
          unawaited(context.push('/onboarding/passphrase'));
        } else {
          setState(() {
            _error = 'App is locked. Unlock to import a view only wallet.'.tr;
            _isImporting = false;
          });
        }
        return;
      }
      if (!appUnlocked && setupPassphrase?.isNotEmpty == true) {
        await widget.securityServices.unlockApp(setupPassphrase!);
        ref.read(appUnlockedProvider.notifier).unlocked = true;
      }

      final birthday = int.tryParse(_birthdayController.text.trim());
      if (birthday == null || birthday < 1) {
        throw ArgumentError('Invalid birthday height'.tr);
      }

      final saplingKey = _saplingIvkController.text.trim();
      final ironwoodKey = _ironwoodIvkController.text.trim();
      if (saplingKey.isEmpty && ironwoodKey.isEmpty) {
        throw ArgumentError('Enter a Sapling or Ironwood viewing key'.tr);
      }

      await ref.read(importViewingWalletProvider)(
        name: _nameController.text.trim(),
        saplingViewingKey: saplingKey.isEmpty ? null : saplingKey,
        ironwoodViewingKey: ironwoodKey.isEmpty ? null : ironwoodKey,
        birthday: birthday,
      );

      if (mounted) {
        ref
            .read(onboardingControllerProvider.notifier)
            .finishViewingKeyImport();
        // Navigate to home with success message
        context.go('/home');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.visibility, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('View only wallet created.'.tr)),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyImportError(e);
        _isImporting = false;
      });
    }
  }

  String _friendlyImportError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('app is locked')) {
      return 'App is locked. Unlock to import a view only wallet.'.tr;
    }
    if (message.contains('invalid sapling viewing key')) {
      return 'Invalid Sapling viewing key format.'.tr;
    }
    return 'Could not continue wallet setup. Try again.'.tr;
  }

  @override
  Widget build(BuildContext context) {
    final basePadding = AppSpacing.screenPadding(
      MediaQuery.of(context).size.width,
      vertical: AppSpacing.xl,
    );
    final contentPadding = basePadding.copyWith(
      bottom: basePadding.bottom + MediaQuery.of(context).viewInsets.bottom,
    );
    return PScaffold(
      bodyMaxWidth: 760,
      title: 'Import viewing keys'.tr,
      appBar: PAppBar(
        title: 'Import viewing keys'.tr,
        subtitle: 'Create a view only wallet'.tr,
        onBack: () => context.pop(),
      ),
      body: SingleChildScrollView(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'View incoming transactions without spending access.'.tr,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Wallet name input
            PInput(
              controller: _nameController,
              label: 'Wallet name'.tr,
              hint: 'e.g., View only wallet'.tr,
            ),

            const SizedBox(height: AppSpacing.lg),

            ViewingKeyFields(
              saplingController: _saplingIvkController,
              ironwoodController: _ironwoodIvkController,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Birthday height input
            PInput(
              controller: _birthdayController,
              label: 'Birthday height'.tr,
              hint: 'Block height when the wallet was created'.tr,
              keyboardType: TextInputType.number,
              helperText: 'Lower values scan more blocks and take longer.'.tr,
            ),

            const SizedBox(height: AppSpacing.lg),

            // Error message
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _error!,
                        style: AppTypography.body.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Security notice
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'A viewing key can view incoming activity but cannot '
                              'spend. Keep your full seed backed up separately.'
                          .tr,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Import button
            PButton(
              text: _isImporting
                  ? 'Importing...'.tr
                  : 'Import view only wallet'.tr,
              onPressed: _isValid && !_isImporting ? _importViewingKeys : null,
              variant: PButtonVariant.primary,
              size: PButtonSize.large,
              isLoading: _isImporting,
            ),
          ],
        ),
      ),
    );
  }
}
