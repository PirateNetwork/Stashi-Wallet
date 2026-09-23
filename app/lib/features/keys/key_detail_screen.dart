import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/ffi/ffi_bridge.dart';
import '../../core/ffi/generated/models.dart'
    show AddressBalanceInfo, KeyAddressInfo, KeyGroupInfo, KeyTypeInfo;
import '../../core/security/biometric_auth.dart';
import '../../core/security/clipboard_manager.dart';
import '../../core/security/decoy_data.dart';
import '../../core/security/screenshot_protection.dart';
import '../../core/providers/wallet_providers.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../../ui/atoms/p_input.dart';
import '../../ui/atoms/p_button.dart';
import '../../ui/molecules/p_card.dart';
import '../../ui/molecules/p_dialog.dart';
import '../../ui/organisms/p_app_bar.dart';
import '../../ui/organisms/p_scaffold.dart';
import '../settings/providers/preferences_providers.dart';
import '../../core/i18n/arb_text_localizer.dart';
import 'key_capabilities.dart';

class KeyDetailScreen extends ConsumerStatefulWidget {
  const KeyDetailScreen({super.key, required this.keyId});

  final int keyId;

  @override
  ConsumerState<KeyDetailScreen> createState() => _KeyDetailScreenState();
}

class _KeyDetailScreenState extends ConsumerState<KeyDetailScreen> {
  Future<_KeyDetailData>? _loadFuture;
  WalletId? _walletId;
  bool _isDecoy = false;
  Timer? _balanceRefreshTimer;
  bool _refreshingBalances = false;
  bool _isGenerating = false;
  bool _isRemoving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setWallet(ref.read(activeWalletProvider), ref.read(decoyModeProvider));
    // Address balances can change even when the total is unchanged (for
    // example, a transfer between this wallet's addresses).
    _balanceRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshBalances());
    });
  }

  @override
  void dispose() {
    _balanceRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant KeyDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyId != widget.keyId) {
      _loadFuture = _walletId == null ? null : _fetchDetail(_walletId!);
    }
  }

  void _setWallet(WalletId? walletId, bool isDecoy) {
    if (_walletId == walletId && _isDecoy == isDecoy) return;
    _walletId = walletId;
    _isDecoy = isDecoy;
    _error = null;
    _loadFuture = walletId == null ? null : _fetchDetail(walletId);
  }

  Future<void> _refreshBalances() async {
    final walletId = _walletId;
    if (walletId == null ||
        _isDecoy ||
        _refreshingBalances ||
        _isGenerating ||
        _isRemoving) {
      return;
    }
    final previousLoad = _loadFuture;
    _refreshingBalances = true;
    try {
      final data = await _fetchDetail(walletId);
      // A wallet/key/mode change or manual refresh supersedes this request.
      if (!mounted || !identical(previousLoad, _loadFuture)) return;
      setState(() {
        _loadFuture = Future.value(data);
      });
    } catch (_) {
      // Keep the last successful snapshot and retry on the next tick.
    } finally {
      _refreshingBalances = false;
    }
  }

  Future<_KeyDetailData> _fetchDetail(WalletId walletId) async {
    final isDecoy = ref.read(decoyModeProvider);
    if (isDecoy) {
      final key = DecoyData.keyGroups().firstWhere(
        (item) => item.id == widget.keyId,
        orElse: () => DecoyData.keyGroups().first,
      );
      final entry = DecoyData.currentAddress();
      final addresses = [
        AddressBalanceInfo(
          address: entry.address,
          balance: BigInt.zero,
          spendable: BigInt.zero,
          pending: BigInt.zero,
          keyId: key.id,
          addressId: 1,
          createdAt: entry.createdAt.millisecondsSinceEpoch ~/ 1000,
          colorTag: GeneratedAddressBookColorTag.none,
          diversifierIndex: entry.index,
        ),
      ];
      return _KeyDetailData(
        key: key,
        addresses: addresses,
        externalAddresses: {entry.address},
      );
    }

    final results = await Future.wait<Object>([
      FfiBridge.listKeyGroups(walletId),
      FfiBridge.listAddressBalances(walletId, keyId: widget.keyId),
      FfiBridge.listAddressesForKey(walletId, widget.keyId),
    ]);
    final keys = results[0] as List<KeyGroupInfo>;
    final addresses = results[1] as List<AddressBalanceInfo>;
    final keyAddresses = results[2] as List<KeyAddressInfo>;
    final externalAddresses = keyAddresses.map((addr) => addr.address).toSet();
    final key = keys.firstWhere(
      (k) => k.id == widget.keyId,
      orElse: () => throw StateError('Key group not found'.tr),
    );
    return _KeyDetailData(
      key: key,
      addresses: addresses,
      externalAddresses: externalAddresses,
    );
  }

  Future<void> _refresh() async {
    final walletId = _walletId;
    if (walletId == null) return;
    setState(() {
      _loadFuture = _fetchDetail(walletId);
    });
  }

  Future<void> _generateAddress({required bool useIronwood}) async {
    final walletId = _walletId;
    if (walletId == null) return;
    final isDecoy = ref.read(decoyModeProvider);
    if (isDecoy) {
      DecoyData.generateNextAddress();
      await _refresh();
      return;
    }
    setState(() {
      _isGenerating = true;
      _error = null;
    });
    try {
      await FfiBridge.generateAddressForKey(
        walletId: walletId,
        keyId: widget.keyId,
        useIronwood: useIronwood,
      );
      await _refresh();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<bool> _authorizeSensitiveKeyAction(String reason) async {
    if (ref.read(decoyModeProvider)) {
      return true;
    }
    final biometricsEnabled = ref.read(biometricsEnabledProvider);
    bool biometricAvailable = false;
    try {
      biometricAvailable = await ref.read(biometricAvailabilityProvider.future);
    } catch (_) {
      biometricAvailable = false;
    }

    if (biometricsEnabled && biometricAvailable) {
      try {
        final authenticated = await BiometricAuth.authenticate(
          reason: reason,
          biometricOnly: true,
        );
        if (authenticated) return true;
      } catch (_) {
        // Fall back to passphrase.
      }
    }

    return _verifyPassphraseDialog();
  }

  Future<bool> _verifyPassphraseDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.backgroundOverlay,
      builder: (_) => const _PassphraseVerificationDialog(),
    );
    return result ?? false;
  }

  Future<void> _exportKeys(KeyGroupInfo key) async {
    final walletId = _walletId;
    if (walletId == null) return;
    setState(() => _error = null);
    final authorized = await _authorizeSensitiveKeyAction(
      'Verify identity to export keys'.tr,
    );
    if (!authorized) return;
    try {
      final isDecoy = ref.read(decoyModeProvider);
      final export = isDecoy
          ? DecoyData.exportKeyGroup(key.id)
          : await FfiBridge.exportKeyGroupKeys(
              walletId: walletId,
              keyId: key.id,
            );
      if (!mounted) return;

      final sections = <Widget?>[
        _buildKeyExportSection(
          'Sapling viewing key'.tr,
          export.saplingViewingKey,
          ClipboardDataType.viewingKey,
        ),
        _buildKeyExportSection(
          'Ironwood viewing key'.tr,
          export.ironwoodViewingKey,
          ClipboardDataType.viewingKey,
        ),
        _buildKeyExportSection(
          'Sapling spending key'.tr,
          export.saplingSpendingKey,
          ClipboardDataType.spendingKey,
        ),
        _buildKeyExportSection(
          'Ironwood spending key'.tr,
          export.ironwoodSpendingKey,
          ClipboardDataType.spendingKey,
        ),
      ].whereType<Widget>().toList();

      if (sections.isEmpty) {
        throw StateError('No exportable keys for this key group.'.tr);
      }

      final protection = ScreenshotProtection.protect();
      try {
        await PDialog.show<void>(
          context: context,
          title: 'Export keys'.tr,
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sections,
              ),
            ),
          ),
          actions: [PDialogAction(label: 'Close'.tr)],
        );
      } finally {
        protection.dispose();
      }
    } catch (e) {
      setState(
        () => _error = 'Failed to export keys: {error}'.trArgs({'error': e}),
      );
    }
  }

  Future<void> _removeImportedKey(KeyGroupInfo key) async {
    final walletId = _walletId;
    if (walletId == null ||
        _isDecoy ||
        _isRemoving ||
        key.keyType != KeyTypeInfo.importedSpending) {
      return;
    }

    final label = key.label?.trim();
    final name = label == null || label.isEmpty
        ? 'Imported spending key'.tr
        : label;
    final confirmed = await PDialog.show<bool>(
      context: context,
      title: 'Remove imported key?'.tr,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Remove “{name}” from this wallet? Its private key and tracked addresses will be removed.'
                .trArgs({'name': name}),
          ),
          SizedBox(height: PSpacing.md),
          Text(
            'Your recovery phrase cannot restore this key. Save the private key first.'
                .tr,
          ),
          SizedBox(height: PSpacing.md),
          Text(
            'Future payments to its old addresses will be missed until you reimport and rescan. Removal requires a fully synced wallet and no unspent funds for this key.'
                .tr,
          ),
        ],
      ),
      actions: [
        PDialogAction(label: 'Cancel'.tr, variant: PButtonVariant.outline),
        PDialogAction<bool>(
          label: 'Continue'.tr,
          variant: PButtonVariant.danger,
          result: true,
        ),
      ],
    );
    if (!mounted || confirmed != true) return;

    final authorized = await _authorizeSensitiveKeyAction(
      'Verify identity to remove an imported key'.tr,
    );
    if (!mounted ||
        !authorized ||
        _walletId != walletId ||
        widget.keyId != key.id ||
        _isDecoy) {
      return;
    }

    setState(() {
      _isRemoving = true;
      _error = null;
    });
    try {
      await FfiBridge.removeImportedSpendingKey(
        walletId: walletId,
        keyId: key.id,
      );
      if (!mounted || _walletId != walletId || widget.keyId != key.id) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported key removed from this wallet.'.tr),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/settings/keys');
    } catch (e) {
      if (mounted && _walletId == walletId && widget.keyId == key.id) {
        setState(
          () => _error = 'Could not remove imported key: {error}'.trArgs({
            'error': e,
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _isRemoving = false);
    }
  }

  Future<void> _copyManagedText(
    String value, {
    required ClipboardDataType dataType,
    required String successMessage,
  }) async {
    switch (dataType) {
      case ClipboardDataType.viewingKey:
        await ClipboardManager.copyViewingKey(value);
        break;
      case ClipboardDataType.spendingKey:
      case ClipboardDataType.seed:
        await ClipboardManager.copySensitive(value, dataType: dataType);
        break;
      case ClipboardDataType.address:
        await ClipboardManager.copyAddress(value);
        break;
      case ClipboardDataType.txid:
      case ClipboardDataType.text:
        await ClipboardManager.copyWithAutoClear(
          value,
          dataType: dataType,
          clearAfter: dataType.clearDelay,
        );
        break;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMessage),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Widget? _buildKeyExportSection(
    String label,
    String? value,
    ClipboardDataType dataType,
  ) {
    if (value == null || value.isEmpty) return null;
    final clearSeconds = dataType.clearDelay.inSeconds;
    return Padding(
      padding: EdgeInsets.only(bottom: PSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: PTypography.labelMedium()),
          SizedBox(height: PSpacing.xs),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: PTypography.codeSmall(color: AppColors.textSecondary),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => _copyManagedText(
                  value,
                  dataType: dataType,
                  successMessage:
                      '$label copied. Clears in $clearSeconds seconds.',
                ),
                tooltip: 'Copy'.tr,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = PSpacing.screenPadding(MediaQuery.of(context).size.width);
    final walletId = ref.watch(activeWalletProvider);
    final isDecoy = ref.watch(decoyModeProvider);
    _setWallet(walletId, isDecoy);

    return PScaffold(
      bodyMaxWidth: 760,
      appBar: PAppBar(
        title: 'Key details'.tr,
        subtitle: 'Manage addresses for this key'.tr,
        showBackButton: true,
      ),
      body: walletId == null
          ? _buildEmptyWallet()
          : FutureBuilder<_KeyDetailData>(
              key: ValueKey((walletId, widget.keyId, isDecoy)),
              future: _loadFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _buildError(
                    snapshot.error?.toString() ??
                        'Failed to load key details'.tr,
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return _buildError('Key details missing'.tr);
                }

                final key = data.key;
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: padding,
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _KeySummaryCard(keyInfo: key),
                          SizedBox(height: PSpacing.lg),
                          _buildActions(context, key),
                          if (_error != null) ...[
                            SizedBox(height: PSpacing.md),
                            Text(
                              _error!,
                              style: PTypography.bodySmall(
                                color: AppColors.error,
                              ),
                            ),
                          ],
                          SizedBox(height: PSpacing.lg),
                          Text('Addresses'.tr, style: PTypography.heading3()),
                          SizedBox(height: PSpacing.xs),
                          Text(
                            'All addresses derived from this key.'.tr,
                            style: PTypography.bodySmall(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          SizedBox(height: PSpacing.md),
                        ]),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        PSpacing.lg,
                        0,
                        PSpacing.lg,
                        PSpacing.lg,
                      ),
                      sliver: data.addresses.isEmpty
                          ? const SliverToBoxAdapter(child: _AddressEmptyCard())
                          : SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final address = data.addresses[index];
                                final isInternal = !data.externalAddresses
                                    .contains(address.address);
                                return Padding(
                                  padding: EdgeInsets.only(bottom: PSpacing.sm),
                                  child: _AddressListItem(
                                    address: address,
                                    isInternal: isInternal,
                                    onCopy: _copyAddress,
                                  ),
                                );
                              }, childCount: data.addresses.length),
                            ),
                    ),
                    if (!_isDecoy &&
                        key.keyType == KeyTypeInfo.importedSpending)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          PSpacing.lg,
                          0,
                          PSpacing.lg,
                          PSpacing.xl,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _buildRemovalCard(key),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildActions(BuildContext context, KeyGroupInfo key) {
    final canGenerateSapling = key.canGenerateSaplingAddresses;
    final canGenerateIronwood = key.canGenerateIronwoodAddresses;

    final actions = <_ActionItem>[
      if (canGenerateSapling)
        _ActionItem(
          label: 'New Sapling address'.tr,
          variant: PButtonVariant.soft,
          onPressed: _isGenerating
              ? null
              : () => _generateAddress(useIronwood: false),
        ),
      if (canGenerateIronwood)
        _ActionItem(
          label: 'New Ironwood address'.tr,
          variant: PButtonVariant.soft,
          onPressed: _isGenerating
              ? null
              : () => _generateAddress(useIronwood: true),
        ),
      if (key.spendable)
        _ActionItem(
          label: 'Consolidate balances'.tr,
          variant: PButtonVariant.soft,
          onPressed: () =>
              context.push('/settings/keys/consolidate?keyId=${key.id}'),
        ),
      if (key.spendable)
        _ActionItem(
          label: 'Sweep balance'.tr,
          variant: PButtonVariant.primary,
          onPressed: () => context.push('/settings/keys/sweep?keyId=${key.id}'),
        ),
      _ActionItem(
        label: 'Export keys'.tr,
        variant: PButtonVariant.soft,
        onPressed: () => _exportKeys(key),
      ),
    ];

    return _buildActionGrid(context, actions);
  }

  Widget _buildRemovalCard(KeyGroupInfo key) {
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Remove imported key'.tr, style: PTypography.heading4()),
          SizedBox(height: PSpacing.xs),
          Text(
            'Only remove this key after saving its private key and moving any funds out.'
                .tr,
            style: PTypography.bodySmall(color: AppColors.textSecondary),
          ),
          SizedBox(height: PSpacing.md),
          PButton(
            onPressed: _isRemoving || _isGenerating
                ? null
                : () => _removeImportedKey(key),
            loading: _isRemoving,
            variant: PButtonVariant.danger,
            icon: const Icon(Icons.delete_outline),
            child: Text('Remove imported key'.tr),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid(BuildContext context, List<_ActionItem> actions) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 3
            : width >= 600
            ? 2
            : 1;
        const spacing = PSpacing.sm;
        final rows = <Widget>[];

        for (var i = 0; i < actions.length; i += columns) {
          var end = i + columns;
          if (end > actions.length) {
            end = actions.length;
          }
          final rowItems = actions.sublist(i, end);

          rows.add(
            Row(
              children: [
                for (
                  var columnIndex = 0;
                  columnIndex < columns;
                  columnIndex++
                ) ...[
                  if (columnIndex > 0) SizedBox(width: spacing),
                  Expanded(
                    child: columnIndex < rowItems.length
                        ? PButton(
                            onPressed: rowItems[columnIndex].onPressed,
                            variant: rowItems[columnIndex].variant,
                            fullWidth: true,
                            child: Text(rowItems[columnIndex].label),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );

          if (i + columns < actions.length) {
            rows.add(SizedBox(height: spacing));
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }

  Widget _buildEmptyWallet() {
    return Center(
      child: Padding(
        padding: PSpacing.screenPadding(MediaQuery.of(context).size.width),
        child: Text('No active wallet.'.tr, style: PTypography.bodyMedium()),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: PSpacing.screenPadding(MediaQuery.of(context).size.width),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 40),
            SizedBox(height: PSpacing.sm),
            Text(
              message,
              style: PTypography.bodyMedium(),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: PSpacing.md),
            PButton(
              onPressed: _refresh,
              variant: PButtonVariant.soft,
              child: Text('Retry'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyAddress(AddressBalanceInfo address) async {
    await _copyManagedText(
      address.address,
      dataType: ClipboardDataType.address,
      successMessage: 'Address copied. Clears in 60 seconds.'.tr,
    );
  }
}

class _PassphraseVerificationDialog extends StatefulWidget {
  const _PassphraseVerificationDialog();

  @override
  State<_PassphraseVerificationDialog> createState() =>
      _PassphraseVerificationDialogState();
}

class _PassphraseVerificationDialogState
    extends State<_PassphraseVerificationDialog> {
  final _controller = TextEditingController();
  bool _isVerifying = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final passphrase = _controller.text.trim();
    if (passphrase.isEmpty) {
      setState(() => _error = 'Enter your passphrase'.tr);
      return;
    }
    setState(() {
      _isVerifying = true;
      _error = null;
    });
    try {
      final ok = await FfiBridge.verifyAppPassphrase(passphrase);
      if (!mounted) return;
      if (ok) {
        _controller.clear();
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = 'Passphrase is incorrect'.tr;
          _isVerifying = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to verify passphrase'.tr;
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.backgroundElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PSpacing.radiusXL),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.84,
        ),
        padding: EdgeInsets.all(PSpacing.dialogPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verify passphrase'.tr,
              style: PTypography.heading4(color: AppColors.textPrimary),
            ),
            SizedBox(height: PSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PInput(
                      controller: _controller,
                      label: 'Passphrase'.tr,
                      hint: 'Enter your wallet passphrase'.tr,
                      obscureText: true,
                      sensitive: true,
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                    if (_error != null) ...[
                      SizedBox(height: PSpacing.sm),
                      Text(
                        _error!,
                        style: PTypography.bodySmall(color: AppColors.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: PSpacing.lg),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: PSpacing.sm,
              runSpacing: PSpacing.sm,
              children: [
                PButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  variant: PButtonVariant.soft,
                  child: Text('Cancel'.tr),
                ),
                PButton(
                  onPressed: _isVerifying ? null : _verify,
                  variant: PButtonVariant.primary,
                  child: Text(_isVerifying ? 'Verifying...'.tr : 'Verify'.tr),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionItem {
  const _ActionItem({
    required this.label,
    required this.variant,
    required this.onPressed,
  });

  final String label;
  final PButtonVariant variant;
  final VoidCallback? onPressed;
}

class _KeySummaryCard extends StatelessWidget {
  const _KeySummaryCard({required this.keyInfo});

  final KeyGroupInfo keyInfo;

  @override
  Widget build(BuildContext context) {
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_displayLabel(keyInfo), style: PTypography.heading3()),
          SizedBox(height: PSpacing.xs),
          Text(
            _subtitle(keyInfo),
            style: PTypography.bodySmall(color: AppColors.textSecondary),
          ),
          SizedBox(height: PSpacing.md),
          Wrap(
            spacing: PSpacing.xs,
            runSpacing: PSpacing.xs,
            children: [
              if (keyInfo.hasSapling)
                _chip('Sapling', AppColors.infoBackground, AppColors.info),
              if (keyInfo.hasIronwood)
                _chip(
                  'Ironwood',
                  AppColors.successBackground,
                  AppColors.success,
                ),
              if (!keyInfo.spendable)
                _chip(
                  'View only'.tr,
                  AppColors.warningBackground,
                  AppColors.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _displayLabel(KeyGroupInfo keyInfo) {
    if (keyInfo.keyType == KeyTypeInfo.seed) {
      final label = keyInfo.label?.trim();
      if (label == null || label.isEmpty || label == 'Seed') {
        return 'Default wallet keys'.tr;
      }
    }
    return keyInfo.label ?? _defaultLabel(keyInfo);
  }

  String _defaultLabel(KeyGroupInfo keyInfo) {
    return switch (keyInfo.keyType) {
      KeyTypeInfo.seed => 'Default wallet keys'.tr,
      KeyTypeInfo.importedSpending => 'Imported spending key'.tr,
      KeyTypeInfo.importedViewing => 'Viewing key'.tr,
    };
  }

  String _subtitle(KeyGroupInfo keyInfo) {
    final type = switch (keyInfo.keyType) {
      KeyTypeInfo.seed => 'Seed phrase keys'.tr,
      KeyTypeInfo.importedSpending => 'Imported spending key'.tr,
      KeyTypeInfo.importedViewing => 'Imported viewing key'.tr,
    };
    return '{type} | Birthday {height}'.trArgs({
      'type': type,
      'height': keyInfo.birthdayHeight,
    });
  }

  Widget _chip(String text, Color background, Color foreground) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: PSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PSpacing.radiusSM),
        border: Border.all(color: foreground.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: PTypography.labelSmall(color: foreground)),
    );
  }
}

class _AddressEmptyCard extends StatelessWidget {
  const _AddressEmptyCard();

  @override
  Widget build(BuildContext context) {
    return PCard(
      child: Padding(
        padding: EdgeInsets.all(PSpacing.lg),
        child: Column(
          children: [
            Icon(Icons.history, color: AppColors.textTertiary, size: 40),
            SizedBox(height: PSpacing.sm),
            Text('No addresses yet.'.tr, style: PTypography.bodyMedium()),
            SizedBox(height: PSpacing.xs),
            Text(
              'Generate a new address to get started.'.tr,
              style: PTypography.bodySmall(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressListItem extends StatelessWidget {
  const _AddressListItem({
    required this.address,
    required this.isInternal,
    required this.onCopy,
  });

  final AddressBalanceInfo address;
  final bool isInternal;
  final ValueChanged<AddressBalanceInfo> onCopy;

  @override
  Widget build(BuildContext context) {
    return PCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _colorTag(address),
              borderRadius: BorderRadius.circular(PSpacing.radiusSM),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined, size: 18),
          ),
          SizedBox(width: PSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  address.label ?? _truncate(address.address),
                  style: PTypography.bodyMedium(),
                ),
                if (isInternal) ...[
                  SizedBox(height: PSpacing.xs),
                  _chip(
                    'Internal change'.tr,
                    AppColors.warning.withValues(alpha: 0.14),
                    AppColors.warning,
                  ),
                ],
                SizedBox(height: PSpacing.xs),
                Text(
                  'Index {index} | {timestamp}'.trArgs({
                    'index': address.diversifierIndex,
                    'timestamp': _formatTimestamp(address.createdAt),
                  }),
                  style: PTypography.bodySmall(color: AppColors.textSecondary),
                ),
                SizedBox(height: PSpacing.xs),
                Text(
                  'Balance {balance}'.trArgs({
                    'balance': _formatArrr(address.balance),
                  }),
                  style: PTypography.bodySmall(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => onCopy(address),
            tooltip: 'Copy address'.tr,
          ),
        ],
      ),
    );
  }

  String _truncate(String address) {
    if (address.length <= 20) return address;
    return '${address.substring(0, 10)}...${address.substring(address.length - 10)}';
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp <= 0) return 'Unknown';
    return timeago.format(
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
    );
  }

  Color _colorTag(AddressBalanceInfo address) {
    final colorTag = AddressBookColorTag.fromValue(address.colorTag.index);
    if (colorTag == AddressBookColorTag.none) {
      return AppColors.backgroundPanel;
    }
    return Color(colorTag.colorValue);
  }

  String _formatArrr(BigInt value) {
    final amount = value.toDouble() / 100000000.0;
    return '${amount.toStringAsFixed(8)} ARRR';
  }

  Widget _chip(String text, Color background, Color foreground) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: PSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PSpacing.radiusSM),
        border: Border.all(color: foreground.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: PTypography.labelSmall(color: foreground)),
    );
  }
}

class _KeyDetailData {
  const _KeyDetailData({
    required this.key,
    required this.addresses,
    required this.externalAddresses,
  });

  final KeyGroupInfo key;
  final List<AddressBalanceInfo> addresses;
  final Set<String> externalAddresses;
}
