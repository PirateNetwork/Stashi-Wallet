// ignore_for_file: noop_primitive_operations

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ffi/generated/models.dart';
import '../../core/formatting/arrr_amount.dart';
import '../../core/providers/wallet_providers.dart';
import '../../core/platform/platform_utils.dart';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../../ui/molecules/connection_status_indicator.dart';
import '../../ui/molecules/p_content_state.dart';
import '../../ui/atoms/p_input.dart';
import '../../ui/molecules/transaction_row_v2.dart';
import '../../ui/molecules/wallet_switcher.dart';
import '../../ui/organisms/p_app_bar.dart';
import '../../ui/organisms/p_scaffold.dart';
import '../../core/i18n/arb_text_localizer.dart';

enum ActivityFilter { all, sent, received, pending, expired }

extension ActivityFilterLabel on ActivityFilter {
  String get label {
    switch (this) {
      case ActivityFilter.all:
        return 'All'.tr;
      case ActivityFilter.sent:
        return 'Sent'.tr;
      case ActivityFilter.received:
        return 'Received'.tr;
      case ActivityFilter.pending:
        return 'Pending'.tr;
      case ActivityFilter.expired:
        return 'Expired'.tr;
    }
  }
}

/// Activity screen showing full transaction history.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, this.useScaffold = true});

  final bool useScaffold;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ActivityFilter _filter = ActivityFilter.all;
  String _query = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearListEnd);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_loadMoreNearListEnd)
      ..dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _loadMoreNearListEnd() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 600) {
      return;
    }
    unawaited(ref.read(activityHistoryProvider.notifier).loadMore());
  }

  void _fillViewportIfNeeded(ActivityHistoryState history) {
    if (!history.hasMore ||
        history.isLoadingMore ||
        history.loadMoreError != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _loadMoreNearListEnd();
    });
  }

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

  List<TxInfo> _applyFilters(List<TxInfo> transactions, int? currentHeight) {
    Iterable<TxInfo> filtered = transactions;

    switch (_filter) {
      case ActivityFilter.sent:
        filtered = filtered.where((tx) => tx.amount < 0);
        break;
      case ActivityFilter.received:
        filtered = filtered.where((tx) => tx.amount >= 0);
        break;
      case ActivityFilter.pending:
        filtered = filtered.where(
          (tx) => !tx.expired && !_isConfirmedTx(tx, currentHeight),
        );
        break;
      case ActivityFilter.expired:
        filtered = filtered.where((tx) => tx.expired);
        break;
      case ActivityFilter.all:
        break;
    }

    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((tx) {
        final memo = tx.memo?.toLowerCase() ?? '';
        // TxInfo doesn't have toAddress - search by txid and memo only
        return tx.txid.toLowerCase().contains(query) || memo.contains(query);
      });
    }

    return filtered.toList();
  }

  /// Convert PlatformInt64 timestamp to DateTime
  DateTime _convertPlatformInt64ToDateTime(PlatformInt64 timestamp) {
    final timestampValue = timestamp.toInt();
    return DateTime.fromMillisecondsSinceEpoch(timestampValue * 1000);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() => _query = value);
      }
    });
  }

  void _clearSearch({bool resetFilter = false}) {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      if (resetFilter) _filter = ActivityFilter.all;
    });
  }

  String _dateLabel(BuildContext context, DateTime date) {
    final today = DateUtils.dateOnly(DateTime.now());
    if (DateUtils.isSameDay(date, today)) return 'Today'.tr;
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    if (DateUtils.isSameDay(date, yesterday)) return 'Yesterday'.tr;
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final historyAsync = ref.watch(activityHistoryProvider);
    // Decryption speed/ETA updates do not change transaction confirmation state.
    // Observe just the chain height instead of rebuilding/filtering every tick.
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
    final screenWidth = size.width;
    final gutter = PSpacing.responsiveGutter(screenWidth);

    final content = historyAsync.when(
      data: (history) {
        final filtered = _applyFilters(history.transactions, currentHeight);
        _fillViewportIfNeeded(history);
        const headerCount = 4;
        final bodyCount = filtered.isEmpty ? 1 : filtered.length;
        final showFooter = filtered.isNotEmpty && history.hasMore;
        final itemCount = headerCount + bodyCount + (showFooter ? 1 : 0);

        return ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            gutter,
            PSpacing.lg,
            gutter,
            PSpacing.lg,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return PInput(
                controller: _searchController,
                label: 'Search'.tr,
                hint: 'Search activity'.tr,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search'.tr,
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      ),
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
              );
            }
            if (index == 1) {
              return const SizedBox(height: PSpacing.md);
            }
            if (index == 2) {
              return _FilterChips(
                selected: _filter,
                onSelected: (filter) => setState(() => _filter = filter),
              );
            }
            if (index == 3) {
              return const SizedBox(height: PSpacing.lg);
            }
            if (filtered.isEmpty) {
              if (history.hasMore) {
                return _ActivityLoadMoreState(
                  error: history.loadMoreError,
                  onRetry: () => unawaited(
                    ref.read(activityHistoryProvider.notifier).retryLoadMore(),
                  ),
                );
              }
              final hasFilters =
                  _filter != ActivityFilter.all || _query.trim().isNotEmpty;
              return PContentState(
                icon: hasFilters
                    ? Icons.search_off
                    : Icons.receipt_long_outlined,
                title: hasFilters
                    ? 'No matching transactions'.tr
                    : 'No activity yet'.tr,
                message: hasFilters
                    ? 'Try a different search or clear your filters.'.tr
                    : 'Your sent and received payments will appear here.'.tr,
                actionLabel: hasFilters
                    ? 'Clear filters'.tr
                    : 'Receive ARRR'.tr,
                onAction: hasFilters
                    ? () => _clearSearch(resetFilter: true)
                    : () => context.push('/receive'),
              );
            }

            final txIndex = index - headerCount;
            if (txIndex >= filtered.length) {
              return _ActivityLoadMoreState(
                error: history.loadMoreError,
                onRetry: () => unawaited(
                  ref.read(activityHistoryProvider.notifier).retryLoadMore(),
                ),
              );
            }
            final tx = filtered[txIndex];
            final date = _convertPlatformInt64ToDateTime(tx.timestamp);
            final showDate =
                txIndex == 0 ||
                !DateUtils.isSameDay(
                  date,
                  _convertPlatformInt64ToDateTime(
                    filtered[txIndex - 1].timestamp,
                  ),
                );
            return Padding(
              key: ValueKey('${tx.txid}:${tx.amount}'),
              padding: const EdgeInsets.only(bottom: PSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDate)
                    Padding(
                      padding: EdgeInsets.only(
                        top: txIndex == 0 ? 0 : PSpacing.xs,
                        bottom: PSpacing.sm,
                      ),
                      child: Semantics(
                        header: true,
                        child: Text(
                          _dateLabel(context, date),
                          style: PTypography.labelMedium(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  TransactionRowV2(
                    isReceived: tx.amount >= 0,
                    isConfirmed: _isConfirmedTx(tx, currentHeight),
                    isExpired: tx.expired,
                    amountText:
                        '${formatArrrAtomic(BigInt.from(tx.amount.toInt()), showPositiveSign: true)} ARRR',
                    timestamp: date,
                    memo: tx.memo,
                    onTap: () => context.push(
                      '/transaction/${tx.txid}?amount=${tx.amount.toInt()}',
                      extra: tx,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => SingleChildScrollView(
        child: PContentState(
          icon: Icons.history,
          title: 'Loading activity'.tr,
          message: 'Your transactions will appear here.'.tr,
          loading: true,
        ),
      ),
      error: (error, _) => SingleChildScrollView(
        child: PContentState(
          icon: Icons.history,
          title: 'Unable to load activity'.tr,
          message: 'Your activity could not be loaded. Try again.'.tr,
          actionLabel: 'Retry'.tr,
          onAction: () => ref.invalidate(activityHistoryProvider),
        ),
      ),
    );

    final isMobile = PSpacing.isHandset(size);
    final isDesktop = isDesktopPlatform;
    final appBarActions = [
      ConnectionStatusIndicator(
        full: !isMobile,
        onTap: () => context.push('/settings/privacy-shield'),
      ),
      if (!isMobile) const WalletSwitcherButton(compact: true),
    ];

    if (!widget.useScaffold) {
      if (isDesktop) {
        return content;
      }
      return PScaffold(
        title: 'Activity'.tr,
        useSafeArea: false,
        appBar: PAppBar(title: 'Activity'.tr, actions: appBarActions),
        body: content,
      );
    }

    return PScaffold(
      title: 'Activity'.tr,
      appBar: isDesktop
          ? null
          : PAppBar(title: 'Activity'.tr, actions: appBarActions),
      body: content,
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final ActivityFilter selected;
  final ValueChanged<ActivityFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ActivityFilter.values.map((filter) {
          final isSelected = filter == selected;
          return Padding(
            padding: const EdgeInsets.only(right: PSpacing.sm),
            child: _FilterChipButton(
              label: filter.label,
              isSelected: isSelected,
              onTap: () => onSelected(filter),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = isSelected
        ? AppColors.selectedBackground
        : AppColors.backgroundSurface;
    final border = isSelected
        ? AppColors.selectedBorder
        : AppColors.borderSubtle;
    final textColor = isSelected
        ? AppColors.textPrimary
        : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PSpacing.radiusFull),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: PSpacing.md,
            vertical: PSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(PSpacing.radiusFull),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: PTypography.labelSmall(color: textColor),
          ),
        ),
      ),
    );
  }
}

class _ActivityLoadMoreState extends StatelessWidget {
  const _ActivityLoadMoreState({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          key: const ValueKey('activity-load-more-error'),
          padding: const EdgeInsets.symmetric(vertical: PSpacing.md),
          child: IconButton(
            tooltip: 'Retry'.tr,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
    }
    return const Center(
      child: Padding(
        key: ValueKey('activity-loading-more'),
        padding: EdgeInsets.symmetric(vertical: PSpacing.lg),
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
