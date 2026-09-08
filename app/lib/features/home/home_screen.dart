/// Home screen - Main wallet dashboard
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../../core/ffi/ffi_bridge.dart';
import '../../core/formatting/arrr_amount.dart';
import '../../core/platform/platform_utils.dart';
import '../../ui/atoms/p_text_button.dart';
import '../../ui/molecules/p_card.dart';
import '../../ui/molecules/p_content_state.dart';
import '../../ui/molecules/transaction_row_v2.dart';
import '../../ui/organisms/balance_hero.dart';
import '../../ui/organisms/p_scaffold.dart';
import '../../core/ffi/generated/models.dart'
    show
        SyncStage,
        SyncStatus,
        TunnelMode_I2p,
        TunnelMode_Socks5,
        TunnelMode_Tor,
        TxInfo;
import '../../core/providers/wallet_providers.dart';
import '../../core/providers/price_providers.dart';
import '../settings/providers/transport_providers.dart';
import '../settings/providers/preferences_providers.dart';
import '../../core/i18n/arb_text_localizer.dart';
import 'widgets/home_header_controls.dart';
import 'widgets/home_sync_indicator.dart';

/// Home screen
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.useScaffold = true});

  static const Key headerKey = Key('home-dashboard-header');
  static const Key headerSurfaceKey = Key('home-dashboard-header-surface');
  static const Key recentActivityTitleKey = Key('recent-activity-title');

  final bool useScaffold;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _hideBalance = false;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final gutter = PSpacing.responsiveGutter(screenWidth);

    final content = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          key: HomeScreen.headerKey,
          child: _HomeHeader(
            padding: EdgeInsets.fromLTRB(
              gutter,
              PSpacing.sm,
              gutter,
              PSpacing.sm,
            ),
            hideBalance: _hideBalance,
            onToggleVisibility: () {
              setState(() => _hideBalance = !_hideBalance);
            },
            showConnectionStatus: widget.useScaffold || !isDesktopPlatform,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              PSpacing.xs,
              gutter,
              PSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.arrow_upward,
                    label: 'Send'.tr,
                    color: AppColors.accentPrimary,
                    onTap: () => context.push('/send'),
                  ),
                ),
                const SizedBox(width: PSpacing.md),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.arrow_downward,
                    label: 'Receive'.tr,
                    color: AppColors.accentSecondary,
                    onTap: () => context.push('/receive'),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, PSpacing.sm),
          sliver: const SliverToBoxAdapter(child: _HomeSyncIndicator()),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              PSpacing.md,
              gutter,
              PSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    key: HomeScreen.recentActivityTitleKey,
                    'Recent activity'.tr,
                    style: PTypography.heading3().copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                PTextButton(
                  label: 'View all'.tr,
                  onPressed: () => context.push('/activity'),
                ),
              ],
            ),
          ),
        ),
        _HomeTransactionsSection(gutter: gutter),
      ],
    );

    if (!widget.useScaffold) {
      return content;
    }

    return PScaffold(title: 'Wallet Home'.tr, body: content);
  }
}

SyncStatus _buildDecoySyncStatus(int height) {
  final safeHeight = height > 0 ? height : 1;
  final blockHeight = BigInt.from(safeHeight);
  return SyncStatus(
    localHeight: blockHeight,
    targetHeight: blockHeight,
    percent: 100.0,
    eta: null,
    stage: SyncStage.verify,
    lastCheckpoint: null,
    blocksPerSecond: 0.0,
    notesDecrypted: BigInt.zero,
    lastBatchMs: BigInt.zero,
  );
}

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({
    required this.padding,
    required this.hideBalance,
    required this.onToggleVisibility,
    required this.showConnectionStatus,
  });

  final EdgeInsets padding;
  final bool hideBalance;
  final VoidCallback onToggleVisibility;
  final bool showConnectionStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(balanceStreamProvider);
    final currency = ref.watch(currencyPreferenceProvider);
    final priceQuote = ref.watch(arrrPriceQuoteProvider).asData?.value;
    final primaryFiat = ref.watch(balancePrimaryFiatProvider);

    final balanceData = balanceAsync.when(
      data: (b) => b,
      loading: () => null,
      error: (_, _) => null,
    );
    final totalBalance = balanceData?.total ?? BigInt.zero;
    // Use backend pending value so "pending change" is shown consistently (matches
    // spendability rules used by send flow).
    final pendingBalance = balanceData?.pending ?? BigInt.zero;
    // Keep balance display stable during incremental sync at tip.
    // Spendability is enforced in send flow, not by zeroing the home balance.
    final displayBalance = totalBalance;
    final balanceArrr = displayBalance.toDouble() / 100000000.0;
    final arrrText =
        '${formatArrrAtomic(displayBalance, minimumFractionDigits: 8, groupThousands: true)} ARRR';
    final fiatAmount = priceQuote == null
        ? null
        : balanceArrr * priceQuote.pricePerArrr;
    final fiatText = fiatAmount == null
        ? null
        : ArrrPriceFormatter.formatCurrency(currency, fiatAmount);
    final showFiatPrimary = primaryFiat && fiatText != null;
    final primaryText = balanceData == null
        ? balanceAsync.hasError
              ? 'Balance unavailable'.tr
              : 'Loading balance...'.tr
        : showFiatPrimary
        ? fiatText
        : arrrText;
    final secondaryText = fiatText == null || balanceData == null
        ? null
        : (showFiatPrimary ? arrrText : fiatText);
    String? balanceHelper;
    if (balanceData != null && balanceArrr <= 0) {
      balanceHelper = 'Share your address to get paid.'.tr;
    } else if (pendingBalance > BigInt.zero) {
      balanceHelper = 'Pending: {amount} ARRR'.trArgs({
        'amount': formatArrrAtomic(pendingBalance, minimumFractionDigits: 8),
      });
    }

    final headerSurface = DecoratedBox(
      key: HomeScreen.headerSurfaceKey,
      decoration: BoxDecoration(color: AppColors.backgroundBase),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeHeaderControls(
                onConnectionTap: () => context.push('/settings/privacy-shield'),
                showConnectionStatus: showConnectionStatus,
              ),
              const SizedBox(height: PSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: BalanceHero(
                  label: 'Balance'.tr,
                  compact: true,
                  balanceText: primaryText,
                  secondaryText: secondaryText,
                  helperText: balanceHelper,
                  isHidden: hideBalance,
                  onToggleVisibility: onToggleVisibility,
                  onSwapDisplay: secondaryText == null
                      ? null
                      : () {
                          ref
                              .read(balancePrimaryFiatProvider.notifier)
                              .setPrimaryFiat(enabled: !primaryFiat);
                        },
                ),
              ),
              if (balanceAsync.hasError && balanceData == null)
                PTextButton(
                  label: 'Retry'.tr,
                  onPressed: () => ref.invalidate(balanceStreamProvider),
                ),
            ],
          ),
        ),
      ),
    );

    return RepaintBoundary(child: headerSurface);
  }
}

class _HomeSyncIndicator extends ConsumerWidget {
  const _HomeSyncIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatusAsync = ref.watch(syncProgressStreamProvider);
    final tunnelMode = ref.watch(tunnelModeProvider);
    final torStatus = ref.watch(torStatusProvider);
    final transportConfig = ref.watch(transportConfigProvider);
    final isDecoy = ref.watch(decoyModeProvider);
    final decoyHeight = ref
        .watch(decoySyncHeightProvider)
        .maybeWhen(data: (height) => height, orElse: () => 0);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final syncStatus = syncStatusAsync.when(
      data: (status) => status,
      loading: () => null,
      error: (_, _) => null,
      skipLoadingOnRefresh: false,
    );

    final decoySyncStatus = isDecoy ? _buildDecoySyncStatus(decoyHeight) : null;
    final i2pEndpoint = transportConfig.i2pEndpoint.trim();
    final i2pEndpointReady =
        tunnelMode is! TunnelMode_I2p || i2pEndpoint.isNotEmpty;
    final usesPrivacyTunnel =
        (tunnelMode is TunnelMode_Tor) ||
        (tunnelMode is TunnelMode_I2p) ||
        (tunnelMode is TunnelMode_Socks5);
    final tunnelReady =
        (tunnelMode is! TunnelMode_Tor || torStatus.isReady) &&
        i2pEndpointReady;
    final tunnelBlocked = !isDecoy && usesPrivacyTunnel && !tunnelReady;

    final displaySyncStatus = isDecoy
        ? decoySyncStatus
        : (tunnelBlocked ? null : syncStatus);
    final currentHeight = displaySyncStatus?.localHeight ?? BigInt.zero;
    final targetHeight = displaySyncStatus?.targetHeight ?? BigInt.zero;
    final isSyncing = !tunnelBlocked && (displaySyncStatus?.isSyncing ?? false);
    final isComplete =
        !tunnelBlocked && (displaySyncStatus?.isComplete ?? false);

    final rawPercent = displaySyncStatus?.percent ?? 0.0;
    final displayPercent = (targetHeight > BigInt.zero)
        ? (isComplete
              ? rawPercent.clamp(0.0, 100.0)
              : rawPercent.clamp(0.0, 99.9))
        : 0.0;
    final syncProgress = displayPercent / 100.0;
    final stage = isComplete
        ? 'Synced'.tr
        : displaySyncStatus?.stageName ??
              (displaySyncStatus != null ? 'Syncing'.tr : 'Not synced'.tr);
    final eta = isComplete
        ? null
        : displaySyncStatus?.etaFormatted ??
              (isSyncing ? 'Calculating...'.tr : null);

    return RepaintBoundary(
      child: HomeSyncIndicator(
        progress: syncProgress,
        currentHeight: currentHeight.toInt(),
        targetHeight: targetHeight.toInt(),
        stage: stage,
        eta: eta,
        blocksPerSecond: displaySyncStatus?.blocksPerSecond ?? 0.0,
        isSyncing: isSyncing,
        isComplete: isComplete,
        reduceMotion: reduceMotion,
      ),
    );
  }
}

class _HomeTransactionsSection extends ConsumerWidget {
  const _HomeTransactionsSection({required this.gutter});

  final double gutter;

  int _confirmationsForTx(TxInfo tx, int? currentHeight) {
    final txHeight = tx.height;
    if (txHeight == null || txHeight <= 0 || currentHeight == null) {
      return 0;
    }
    if (currentHeight < txHeight) {
      return 0;
    }
    return (currentHeight - txHeight) + 1;
  }

  bool _isConfirmedTx(TxInfo tx, int? currentHeight) {
    if (tx.confirmed) {
      return true;
    }
    return _confirmationsForTx(tx, currentHeight) >= 1;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsProvider);
    final isSyncing = ref.watch(
      syncProgressStreamProvider.select(
        (value) => value.maybeWhen(
          data: (status) => status?.isSyncing ?? false,
          orElse: () => false,
        ),
      ),
    );
    final progressHeight = ref.watch(
      syncProgressStreamProvider.select((value) {
        final status = value.asData?.value;
        return (status?.targetHeight ?? status?.localHeight)?.toInt();
      }),
    );
    final fallbackHeight = ref.watch(
      syncStatusProvider.select((value) {
        final status = value.asData?.value;
        return (status?.targetHeight ?? status?.localHeight)?.toInt();
      }),
    );
    final currentHeight = progressHeight ?? fallbackHeight;

    final transactions = transactionsAsync.asData?.value ?? const <TxInfo>[];

    if (transactionsAsync.hasError && transactions.isEmpty) {
      return SliverToBoxAdapter(
        child: PContentState(
          icon: Icons.history,
          title: 'Unable to load activity'.tr,
          message: 'Your activity could not be loaded. Try again.'.tr,
          actionLabel: 'Retry'.tr,
          onAction: () => ref.invalidate(transactionsProvider),
        ),
      );
    }

    if (transactionsAsync.isLoading && transactions.isEmpty) {
      return SliverToBoxAdapter(
        child: PContentState(
          icon: Icons.history,
          title: 'Loading activity'.tr,
          message: 'Your transactions will appear here.'.tr,
          loading: true,
        ),
      );
    }

    if (transactions.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            PSpacing.xl,
            gutter,
            PSpacing.xl,
          ),
          child: PContentState(
            icon: Icons.arrow_downward,
            title: isSyncing ? 'Syncing activity...'.tr : 'No activity yet'.tr,
            message: isSyncing
                ? 'Transactions will appear as your wallet catches up.'.tr
                : 'Share your private address to receive ARRR.'.tr,
            actionLabel: isSyncing ? null : 'Receive ARRR'.tr,
            onAction: isSyncing ? null : () => context.push('/receive'),
          ),
        ),
      );
    }

    final itemCount = transactions.length > 10 ? 10 : transactions.length;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, PSpacing.lg),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= itemCount) return null;
          final tx = transactions[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == itemCount - 1 ? 0 : PSpacing.sm,
            ),
            child: _TransactionItemWithLabel(
              key: ValueKey(tx.txid),
              tx: tx,
              isConfirmed: _isConfirmedTx(tx, currentHeight),
              onTap: () => context.push(
                '/transaction/${tx.txid}?amount=${tx.amount}',
                extra: tx,
              ),
            ),
          );
        }, childCount: itemCount),
      ),
    );
  }
}

/// Quick action button
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PCard(
      onTap: onTap,
      padding: const EdgeInsets.all(PSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(PSpacing.xs),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: PSpacing.sm),
            Flexible(
              child: Text(
                label,
                style: PTypography.bodyMedium().copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Transaction item with address book label lookup
class _TransactionItemWithLabel extends StatelessWidget {
  final TxInfo tx;
  final bool isConfirmed;
  final VoidCallback? onTap;

  const _TransactionItemWithLabel({
    super.key,
    required this.tx,
    required this.isConfirmed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Convert PlatformInt64 to int for calculations
    final amountValue = tx.amount;
    final isReceived = amountValue >= 0;

    // Convert PlatformInt64 timestamp to DateTime
    final timestampValue = tx.timestamp;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      timestampValue * 1000,
    );

    return TransactionRowV2(
      isReceived: isReceived,
      isConfirmed: isConfirmed,
      isExpired: tx.expired,
      amountText:
          '${formatArrrAtomic(BigInt.from(amountValue), showPositiveSign: true)} ARRR',
      timestamp: timestamp,
      memo: tx.memo,
      onTap: onTap,
    );
  }
}
