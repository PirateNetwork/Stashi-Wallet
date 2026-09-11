// ignore_for_file: noop_primitive_operations

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ffi/ffi_bridge.dart';
import '../../core/ffi/generated/models.dart';
import '../../core/providers/wallet_providers.dart';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../../ui/molecules/p_card.dart';
import '../../core/formatting/arrr_amount.dart';
import '../../ui/organisms/p_app_bar.dart';
import '../../ui/organisms/p_scaffold.dart';
import '../../ui/organisms/p_skeleton.dart';
import '../../core/i18n/arb_text_localizer.dart';
import 'payment_disclosures_provider.dart';

/// Transaction detail screen.
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({
    super.key,
    required this.txid,
    this.amount,
    this.transaction,
  });

  final String txid;
  final int? amount;
  final TxInfo? transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    TxInfo? findTransaction(Iterable<TxInfo> transactions) {
      if (amount != null) {
        for (final item in transactions) {
          if (item.txid == txid && item.amount.toInt() == amount) {
            return item;
          }
        }
      }
      return transactions.where((item) => item.txid == txid).firstOrNull;
    }

    final routedTransaction = transaction != null
        ? findTransaction([transaction!])
        : null;
    final Widget content;
    if (routedTransaction != null) {
      content = _TransactionDetails(tx: routedTransaction);
    } else {
      content = ref
          .watch(transactionsProvider)
          .when(
            data: (txs) {
              final tx = findTransaction(txs);
              if (tx == null) {
                return _TransactionMissing(txid: txid);
              }
              return _TransactionDetails(tx: tx);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _TransactionError(message: error.toString()),
          );
    }

    return PScaffold(
      title: 'Transaction'.tr,
      appBar: PAppBar(title: 'Transaction'.tr, showBackButton: true),
      bodyMaxWidth: 760,
      body: content,
    );
  }
}

class _TransactionDetails extends ConsumerStatefulWidget {
  const _TransactionDetails({required this.tx});

  final TxInfo tx;

  @override
  ConsumerState<_TransactionDetails> createState() =>
      _TransactionDetailsState();
}

class _TransactionDetailsState extends ConsumerState<_TransactionDetails> {
  static const _transactionIdStorageKey = PageStorageKey('transaction-id-text');
  Future<String?>? _memoFuture;

  @override
  void initState() {
    super.initState();
    _refreshMemoFuture();
  }

  @override
  void didUpdateWidget(covariant _TransactionDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tx.txid != widget.tx.txid ||
        oldWidget.tx.amount != widget.tx.amount ||
        oldWidget.tx.expired != widget.tx.expired ||
        (oldWidget.tx.memo ?? '') != (widget.tx.memo ?? '')) {
      _refreshMemoFuture();
    }
  }

  void _refreshMemoFuture() {
    final walletId = ref.read(activeWalletProvider);
    if (walletId == null) {
      _memoFuture = null;
      return;
    }
    if (widget.tx.memo != null && widget.tx.memo!.isNotEmpty) {
      _memoFuture = null;
      return;
    }
    _memoFuture =
        FfiBridge.fetchTransactionMemo(
          walletId: walletId,
          txid: widget.tx.txid,
        ).then((memo) {
          if (mounted && memo != null && memo.isNotEmpty) {
            ref.invalidate(transactionsProvider);
          }
          return memo;
        });
  }

  /// Convert PlatformInt64 timestamp to DateTime
  DateTime _convertTimestamp(PlatformInt64 timestamp) {
    final timestampValue = timestamp.toInt();
    return DateTime.fromMillisecondsSinceEpoch(timestampValue * 1000);
  }

  int _confirmationsFor({required int? txHeight, required int? currentHeight}) {
    if (txHeight == null || txHeight <= 0 || currentHeight == null) {
      return 0;
    }
    if (currentHeight < txHeight) {
      return 0;
    }
    return (currentHeight - txHeight) + 1;
  }

  int _displayFeeArrrtoshis(TxInfo tx) {
    final recordedFee = tx.fee.toInt();
    if (recordedFee > 0) {
      return recordedFee;
    }
    // Some historic records have missing stored fees for outgoing txs.
    // Pirate uses a fixed minimum fee, so show that instead of 0.
    if (tx.amount < 0) {
      return FfiBridge.minFee;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final padding = PSpacing.screenPadding(MediaQuery.of(context).size.width);
    final tx = widget.tx;
    final isReceived = tx.amount >= 0;
    final walletId = ref.watch(activeWalletProvider);
    final disclosureProvider = walletId != null && !isReceived && !tx.expired
        ? paymentDisclosuresProvider((walletId: walletId, txid: tx.txid))
        : null;
    final disclosures = disclosureProvider == null
        ? null
        : ref.watch(disclosureProvider);
    final showNetworkFee = !isReceived;
    final amountArrr = _formatArrr(tx.amount.abs());
    final displayFeeArrrtoshis = _displayFeeArrrtoshis(tx);
    final feeArrr = _formatArrr(displayFeeArrrtoshis);
    final syncProgressStatus = ref
        .watch(syncProgressStreamProvider)
        .asData
        ?.value;
    final syncStatus = ref.watch(syncStatusProvider).asData?.value;
    final currentHeight =
        (syncProgressStatus?.targetHeight ??
                syncProgressStatus?.localHeight ??
                syncStatus?.targetHeight ??
                syncStatus?.localHeight)
            ?.toInt();
    final confirmations = _confirmationsFor(
      txHeight: tx.height,
      currentHeight: currentHeight,
    );
    final isConfirmed = tx.confirmed || confirmations >= 1;
    final statusText = tx.expired
        ? 'Expired'.tr
        : isConfirmed
        ? 'Confirmed'.tr
        : 'Pending'.tr;
    final statusColor = tx.expired
        ? AppColors.error
        : isConfirmed
        ? AppColors.success
        : AppColors.warning;
    final timestamp = _convertTimestamp(tx.timestamp);
    final localizations = MaterialLocalizations.of(context);
    final dateText = localizations.formatFullDate(timestamp);
    final timeText = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(timestamp),
    );

    return ListView(
      padding: padding,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: PSpacing.lg),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  tx.expired
                      ? Icons.timer_off_outlined
                      : (isReceived
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded),
                  color: statusColor,
                  size: 26,
                ),
              ),
              const SizedBox(height: PSpacing.md),
              Text(
                isReceived ? 'Received'.tr : 'Sent'.tr,
                style: PTypography.bodyMedium(color: AppColors.textSecondary),
              ),
              const SizedBox(height: PSpacing.xs),
              Semantics(
                label: amountArrr,
                excludeSemantics: true,
                child: Column(
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatArrrAtomic(
                          BigInt.from(tx.amount.toInt()).abs(),
                          minimumFractionDigits: 0,
                          groupThousands: true,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        style:
                            PTypography.displaySmall(
                              color: AppColors.textPrimary,
                            ).copyWith(
                              fontSize: 40,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                    const SizedBox(height: PSpacing.xxs),
                    Text(
                      'ARRR',
                      style: PTypography.bodyMedium(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: PSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: PSpacing.sm,
                  vertical: PSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(PSpacing.radiusFull),
                ),
                child: Text(
                  statusText,
                  style: PTypography.labelSmall(color: statusColor),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: PSpacing.md),
        PCard(
          padding: const EdgeInsets.all(PSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DetailRow(label: 'Date'.tr, value: dateText),
              const SizedBox(height: PSpacing.md),
              _DetailRow(label: 'Time'.tr, value: timeText),
              if (showNetworkFee) ...[
                const SizedBox(height: PSpacing.md),
                _DetailRow(label: 'Network fee'.tr, value: feeArrr),
              ],
            ],
          ),
        ),
        if (tx.expired) ...[
          const SizedBox(height: PSpacing.lg),
          PCard(
            child: Padding(
              padding: const EdgeInsets.all(PSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(PSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.timer_off_outlined,
                      color: AppColors.error,
                      size: PSpacing.iconMD,
                    ),
                  ),
                  const SizedBox(width: PSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transaction expired'.tr,
                          style: PTypography.titleMedium(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: PSpacing.xs),
                        Text(
                          'This payment did not confirm before it expired. Its locked funds are available to spend again. Create a new payment if you still want to send it.'
                              .tr,
                          style: PTypography.bodySmall(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (displayFeeArrrtoshis > 0 &&
            tx.amount.abs() == displayFeeArrrtoshis) ...[
          const SizedBox(height: PSpacing.lg),
          PCard(
            child: Padding(
              padding: const EdgeInsets.all(PSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.swap_horiz,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: PSpacing.sm),
                  Expanded(
                    child: Text(
                      'Internal transfer between your addresses. Net change equals the network fee.'
                          .tr,
                      style: PTypography.bodySmall(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (tx.memo != null && tx.memo!.isNotEmpty) ...[
          const SizedBox(height: PSpacing.lg),
          _MemoCard(memo: tx.memo!),
        ] else if (_memoFuture != null) ...[
          const SizedBox(height: PSpacing.lg),
          FutureBuilder<String?>(
            future: _memoFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _MemoLoadingCard();
              }
              final memo = snapshot.data;
              if (memo == null || memo.isEmpty) {
                return const SizedBox.shrink();
              }
              return _MemoCard(memo: memo);
            },
          ),
        ],
        const SizedBox(height: PSpacing.lg),
        PCard(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            key: const PageStorageKey('transaction-technical-details'),
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: PSpacing.lg,
              vertical: PSpacing.xs,
            ),
            title: Text(
              'Technical details'.tr,
              style: PTypography.bodyMedium(color: AppColors.textPrimary),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              PSpacing.lg,
              0,
              PSpacing.lg,
              PSpacing.lg,
            ),
            children: [
              if (tx.height != null) ...[
                _DetailRow(
                  label: 'Block height'.tr,
                  value: tx.height.toString(),
                ),
                const SizedBox(height: PSpacing.md),
                _DetailRow(
                  label: 'Confirmations'.tr,
                  value: confirmations.toString(),
                ),
                const SizedBox(height: PSpacing.md),
              ],
              if (tx.expiryHeight != null) ...[
                _DetailRow(
                  label: 'Expiry'.tr,
                  value: tx.expiryHeight.toString(),
                ),
                const SizedBox(height: PSpacing.md),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Transaction ID'.tr,
                      style: PTypography.bodySmall(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: tx.txid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Transaction ID copied'.tr)),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy transaction ID'.tr,
                  ),
                ],
              ),
              SelectableText(
                key: _transactionIdStorageKey,
                tx.txid,
                style: PTypography.codeMedium(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
        if (disclosures != null) ...[
          const SizedBox(height: PSpacing.lg),
          disclosures.when(
            loading: () => const _PaymentDisclosureLoadingCard(),
            error: (_, _) => _PaymentDisclosureUnavailableCard(
              onRetry: () => ref.invalidate(disclosureProvider!),
            ),
            data: (items) => items.isEmpty
                ? const SizedBox.shrink()
                : _PaymentDisclosureCard(disclosures: items),
          ),
        ],
      ],
    );
  }

  String _formatArrr(int arrrtoshis) {
    return '${formatArrrAtomic(BigInt.from(arrrtoshis), minimumFractionDigits: 0, groupThousands: true)} ARRR';
  }
}

class _PaymentDisclosureCard extends StatelessWidget {
  const _PaymentDisclosureCard({required this.disclosures});

  final List<PaymentDisclosure> disclosures;

  @override
  Widget build(BuildContext context) {
    return PCard(
      child: Padding(
        padding: const EdgeInsets.all(PSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment disclosure'.tr,
              style: PTypography.titleMedium(color: AppColors.textPrimary),
            ),
            const SizedBox(height: PSpacing.sm),
            Text(
              'Share a disclosure only when you want someone to verify this specific sent output. It does not reveal your full wallet history.'
                  .tr,
              style: PTypography.bodySmall(color: AppColors.textSecondary),
            ),
            const SizedBox(height: PSpacing.md),
            for (var i = 0; i < disclosures.length; i++) ...[
              if (i > 0) const SizedBox(height: PSpacing.md),
              _PaymentDisclosureTile(
                disclosure: disclosures[i],
                showRecipient: disclosures.length > 1,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentDisclosureTile extends StatelessWidget {
  const _PaymentDisclosureTile({
    required this.disclosure,
    required this.showRecipient,
  });

  final PaymentDisclosure disclosure;
  final bool showRecipient;

  @override
  Widget build(BuildContext context) {
    final pool = _titleCase(disclosure.disclosureType);
    final amount = _formatArrr(disclosure.amount.toInt());
    final label = '$pool #${disclosure.outputIndex}';

    return Container(
      padding: const EdgeInsets.all(PSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(PSpacing.radiusMD),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$label · $amount',
                  style: PTypography.labelMedium(color: AppColors.textPrimary),
                ),
              ),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: disclosure.disclosure));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Payment disclosure copied'.tr)),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy payment disclosure'.tr,
                color: AppColors.textSecondary,
              ),
            ],
          ),
          if (showRecipient) ...[
            const SizedBox(height: PSpacing.xxs),
            Text(
              _middleEllipsis(disclosure.address),
              style: PTypography.bodySmall(color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: PSpacing.xs),
          SelectableText(
            disclosure.disclosure,
            style: PTypography.codeMedium(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  String _formatArrr(int arrrtoshis) {
    return '${formatArrrAtomic(BigInt.from(arrrtoshis), minimumFractionDigits: 0, groupThousands: true)} ARRR';
  }

  String _middleEllipsis(String value) {
    if (value.length <= 26) {
      return value;
    }
    return '${value.substring(0, 12)}...${value.substring(value.length - 10)}';
  }

  String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _PaymentDisclosureLoadingCard extends StatelessWidget {
  const _PaymentDisclosureLoadingCard();

  @override
  Widget build(BuildContext context) {
    return PCard(
      child: Padding(
        padding: const EdgeInsets.all(PSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            PSkeleton(width: 150, height: 18),
            SizedBox(height: PSpacing.sm),
            PSkeleton(width: double.infinity, height: 14),
            SizedBox(height: PSpacing.md),
            PSkeleton(width: double.infinity, height: 72),
          ],
        ),
      ),
    );
  }
}

class _PaymentDisclosureUnavailableCard extends StatelessWidget {
  const _PaymentDisclosureUnavailableCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return PCard(
      child: Padding(
        padding: const EdgeInsets.all(PSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: AppColors.textTertiary, size: 20),
            const SizedBox(width: PSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment disclosure unavailable'.tr,
                    style: PTypography.titleSmall(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: PSpacing.xxs),
                  Text(
                    'Try again after the transaction is confirmed and the wallet is synced.'
                        .tr,
                    style: PTypography.bodySmall(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  TextButton(onPressed: onRetry, child: Text('Retry'.tr)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: PTypography.bodySmall(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: PSpacing.sm),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: PTypography.bodySmall(color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _MemoCard extends StatelessWidget {
  const _MemoCard({required this.memo});

  final String memo;

  @override
  Widget build(BuildContext context) {
    return PCard(
      child: Padding(
        padding: const EdgeInsets.all(PSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Memo'.tr,
                  style: PTypography.titleMedium(color: AppColors.textPrimary),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: memo));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Memo copied'.tr)));
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy memo'.tr,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: PSpacing.sm),
            SelectableText(
              memo,
              style: PTypography.bodySmall(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoLoadingCard extends StatelessWidget {
  const _MemoLoadingCard();

  @override
  Widget build(BuildContext context) {
    return PCard(
      child: Padding(
        padding: const EdgeInsets.all(PSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            PSkeleton(width: 64, height: 18),
            SizedBox(height: PSpacing.sm),
            PSkeleton(width: double.infinity, height: 14),
            SizedBox(height: PSpacing.xs),
            PSkeleton(width: 220, height: 14),
          ],
        ),
      ),
    );
  }
}

class _TransactionMissing extends StatelessWidget {
  const _TransactionMissing({required this.txid});

  final String txid;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: PSpacing.screenPadding(
          MediaQuery.of(context).size.width,
          vertical: PSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: PSpacing.md),
            Text(
              'Transaction not found'.tr,
              style: PTypography.titleMedium(color: AppColors.textPrimary),
            ),
            const SizedBox(height: PSpacing.xs),
            SelectableText(
              txid,
              style: PTypography.bodySmall(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionError extends StatelessWidget {
  const _TransactionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: PSpacing.screenPadding(
          MediaQuery.of(context).size.width,
          vertical: PSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: PSpacing.md),
            Text(
              'Unable to load transaction'.tr,
              style: PTypography.titleMedium(color: AppColors.textPrimary),
            ),
            const SizedBox(height: PSpacing.xs),
            Text(
              message,
              style: PTypography.bodySmall(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
