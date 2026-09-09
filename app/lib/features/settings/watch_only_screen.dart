import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/atoms/p_button.dart';
import '../../ui/atoms/p_input.dart';
import '../../ui/molecules/viewing_key_fields.dart';
import '../../ui/atoms/p_text_button.dart';
import '../../design/compat.dart';
import '../../design/tokens/colors.dart';
import '../../ui/organisms/p_app_bar.dart';
import '../../ui/organisms/p_scaffold.dart';
import '../../core/ffi/ffi_bridge.dart';
import '../../core/providers/wallet_providers.dart';
import '../../core/security/clipboard_manager.dart';
import '../../core/security/decoy_data.dart';
import '../../core/security/viewing_key_export.dart';
import '../../core/security/screenshot_protection.dart';
import '../../core/i18n/arb_text_localizer.dart';

/// Watch-Only Wallet Management Screen
class WatchOnlyScreen extends ConsumerStatefulWidget {
  const WatchOnlyScreen({super.key});

  @override
  ConsumerState<WatchOnlyScreen> createState() => _WatchOnlyScreenState();
}

class _WatchOnlyScreenState extends ConsumerState<WatchOnlyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PScaffold(
      bodyMaxWidth: 760,
      title: 'View Only Wallets'.tr,
      appBar: PAppBar(
        title: 'View Only Wallets'.tr,
        subtitle: 'View only'.tr,
        showBackButton: true,
      ),
      body: ColoredBox(
        color: AppColors.backgroundBase,
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: TabBar(
                controller: _tabController,
                indicatorColor: PirateTheme.accentColor,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textSecondary,
                tabs: [
                  Tab(text: 'Export'.tr),
                  Tab(text: 'Import'.tr),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  ExportSaplingViewingKeyTab(),
                  ImportSaplingViewingKeyTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Export Sapling viewing key tab
class ExportSaplingViewingKeyTab extends ConsumerStatefulWidget {
  const ExportSaplingViewingKeyTab({super.key});

  @override
  ConsumerState<ExportSaplingViewingKeyTab> createState() =>
      _ExportSaplingViewingKeyTabState();
}

class _ExportSaplingViewingKeyTabState
    extends ConsumerState<ExportSaplingViewingKeyTab> {
  String? _ivk;
  bool _isLoading = false;
  String? _error;
  ScreenProtection? _screenProtection;

  @override
  void dispose() {
    _enableScreenshots();
    super.dispose();
  }

  void _disableScreenshots() {
    if (_screenProtection != null) return;
    _screenProtection = ScreenshotProtection.protect();
  }

  void _enableScreenshots() {
    _screenProtection?.dispose();
    _screenProtection = null;
  }

  @override
  Widget build(BuildContext context) {
    final basePadding = PirateSpacing.screenPadding(
      MediaQuery.of(context).size.width,
      vertical: PirateSpacing.lg,
    );
    final padding = basePadding.copyWith(
      bottom: basePadding.bottom + MediaQuery.of(context).viewInsets.bottom,
    );
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.visibility, size: 80, color: PirateTheme.accentColor),
          SizedBox(height: PirateSpacing.xl),
          Text(
            'Viewing key'.tr,
            style: PirateTypography.h2.copyWith(color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: PirateSpacing.md),
          Text(
            'View incoming transactions without spending access.'.tr,
            style: PirateTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: PirateSpacing.xxl),
          _buildInfoCard(),
          SizedBox(height: PirateSpacing.xl),
          if (_ivk == null) ...[
            PButton(
              onPressed: _exportSaplingViewingKey,
              loading: _isLoading,
              icon: const Icon(Icons.key),
              child: Text('Export'.tr),
            ),
          ] else ...[
            _buildIvkDisplay(),
            SizedBox(height: PirateSpacing.lg),
            PButton(
              onPressed: _copyIvk,
              icon: const Icon(Icons.copy),
              variant: PButtonVariant.outline,
              child: Text('Copy to clipboard'.tr),
            ),
            SizedBox(height: PirateSpacing.md),
            PTextButton(
              label: 'Clear'.tr,
              onPressed: () async {
                await ClipboardManager.clearNow();
                _enableScreenshots();
                setState(() => _ivk = null);
              },
              variant: PTextButtonVariant.subtle,
            ),
          ],
          if (_error != null) ...[
            SizedBox(height: PirateSpacing.lg),
            Container(
              padding: EdgeInsets.all(PirateSpacing.md),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: PirateTypography.body.copyWith(color: Colors.red[400]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: EdgeInsets.all(PirateSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info, color: Colors.blue, size: 24),
              SizedBox(width: PirateSpacing.sm),
              Expanded(
                child: Text(
                  'About viewing keys'.tr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PirateTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: PirateSpacing.md),
          _buildInfoItem('View incoming transactions'.tr),
          _buildInfoItem('Cannot spend'.tr),
          _buildInfoItem('Useful for accounting'.tr),
          _buildInfoItem(
            'Keep viewing keys private. They reveal incoming history.'.tr,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: PirateSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, color: Colors.blue, size: 6),
          SizedBox(width: PirateSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: PirateTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _keyLabel =>
      (_ivk?.startsWith('pirate-extended-viewing-key1') ?? false)
      ? 'Ironwood viewing key'.tr
      : 'Sapling viewing key'.tr;

  Widget _buildIvkDisplay() {
    return Container(
      padding: EdgeInsets.all(PirateSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.backgroundSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _keyLabel,
            style: PirateTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: PirateSpacing.sm),
          SelectableText(
            _ivk!,
            style: PirateTypography.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportSaplingViewingKey() async {
    if (ref.read(decoyModeProvider)) {
      setState(
        () =>
            _ivk = DecoyData.exportKeyGroup(DecoyData.keyGroups().first.id)
                .saplingViewingKey,
      );
      _disableScreenshots();
      return;
    }
    if (!await _verifyExport() || !mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final walletId = await FfiBridge.getActiveWallet();
      if (walletId == null) {
        throw StateError('No active wallet'.tr);
      }

      final ivk = await exportCurrentAddressViewingKey(walletId);
      if (!mounted) return;
      setState(() => _ivk = ivk);
      _disableScreenshots();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = 'Failed to export keys: {error}'.trArgs({'error': e}),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _verifyExport() async {
    final controller = TextEditingController();
    var busy = false;
    String? error;
    final verified = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Verify passphrase'.tr),
          content: PInput(
            controller: controller,
            label: 'Passphrase'.tr,
            obscureText: true,
            sensitive: true,
            enabled: !busy,
            errorText: error,
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context, false),
              child: Text('Cancel'.tr),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      update(() => busy = true);
                      try {
                        final valid = await FfiBridge.verifyAppPassphrase(
                          controller.text,
                        );
                        if (!context.mounted) return;
                        if (valid) {
                          controller.clear();
                          Navigator.pop(context, true);
                          return;
                        }
                        update(() => error = 'Passphrase is incorrect'.tr);
                      } catch (_) {
                        if (!context.mounted) return;
                        update(() => error = 'Unable to verify passphrase'.tr);
                      }
                      if (context.mounted) update(() => busy = false);
                    },
              child: Text(busy ? 'Verifying...'.tr : 'Verify'.tr),
            ),
          ],
        ),
      ),
    );
    // The dialog route still animates out after its result completes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    return verified ?? false;
  }

  Future<void> _copyIvk() async {
    if (_ivk == null) return;

    await ClipboardManager.copyViewingKey(_ivk!);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Viewing key copied. Clears in 30 seconds.'.tr),
          backgroundColor: Colors.green[700],
        ),
      );
    }
  }
}

/// Import Sapling viewing key tab
class ImportSaplingViewingKeyTab extends ConsumerStatefulWidget {
  const ImportSaplingViewingKeyTab({super.key});

  @override
  ConsumerState<ImportSaplingViewingKeyTab> createState() =>
      _ImportSaplingViewingKeyTabState();
}

class _ImportSaplingViewingKeyTabState
    extends ConsumerState<ImportSaplingViewingKeyTab> {
  final _nameController = TextEditingController();
  final _ivkController = TextEditingController();
  final _ironwoodController = TextEditingController();
  final _birthdayController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<int?> _getDefaultBirthdayHeight() async {
    try {
      return await FfiBridge.getDefaultBirthdayHeight();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ivkController.dispose();
    _ironwoodController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final basePadding = PirateSpacing.screenPadding(
      MediaQuery.of(context).size.width,
      vertical: PirateSpacing.lg,
    );
    final padding = basePadding.copyWith(
      bottom: basePadding.bottom + MediaQuery.of(context).viewInsets.bottom,
    );
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'View incoming transactions without spending access.'.tr,
            style: PirateTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: PirateSpacing.lg),
          PInput(
            controller: _nameController,
            label: 'Wallet name'.tr,
            hint: 'e.g., Savings (view only)'.tr,
          ),
          SizedBox(height: PirateSpacing.lg),
          ViewingKeyFields(
            saplingController: _ivkController,
            ironwoodController: _ironwoodController,
          ),
          SizedBox(height: PirateSpacing.lg),
          PInput(
            controller: _birthdayController,
            label: 'Birthday height (optional)'.tr,
            hint: 'e.g., 4000000',
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: PirateSpacing.md),
          Text(
            'Birthday height helps speed up initial sync. Leave blank to use the default height.'
                .tr,
            style: PirateTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (_error != null) ...[
            SizedBox(height: PirateSpacing.lg),
            Container(
              padding: EdgeInsets.all(PirateSpacing.md),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: PirateTypography.body.copyWith(color: Colors.red[400]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          SizedBox(height: PirateSpacing.xxl),
          PButton(
            onPressed: _importWallet,
            loading: _isLoading,
            icon: const Icon(Icons.add),
            child: Text('Import view only wallet'.tr),
          ),
        ],
      ),
    );
  }

  Future<void> _importWallet() async {
    // Validate inputs
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a wallet name'.tr);
      return;
    }

    final saplingKey = _ivkController.text.trim();
    final ironwoodKey = _ironwoodController.text.trim();
    if (saplingKey.isEmpty && ironwoodKey.isEmpty) {
      setState(() => _error = 'Provide a viewing key'.tr);
      return;
    }
    final birthdayText = _birthdayController.text.trim();
    if (birthdayText.isNotEmpty && (int.tryParse(birthdayText) ?? 0) < 1) {
      setState(() => _error = 'Enter a valid birthday height'.tr);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final birthday = _birthdayController.text.isNotEmpty
          ? int.tryParse(_birthdayController.text)
          : null;
      final fallbackBirthday = birthday ?? await _getDefaultBirthdayHeight();
      if (fallbackBirthday == null) {
        throw StateError('Failed to resolve a default birthday height.'.tr);
      }

      await ref.read(importViewingWalletProvider)(
        name: _nameController.text.trim(),
        saplingViewingKey: saplingKey.isEmpty ? null : saplingKey,
        ironwoodViewingKey: ironwoodKey.isEmpty ? null : ironwoodKey,
        birthday: fallbackBirthday,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('View only wallet imported.'.tr),
            backgroundColor: Colors.green[700],
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = 'Failed to import wallet: {error}'.trArgs({'error': e}),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
