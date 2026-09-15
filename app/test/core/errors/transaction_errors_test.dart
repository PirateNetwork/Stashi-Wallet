import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/errors/transaction_errors.dart';

void main() {
  test('shielded spend conflicts are not reported as successful sends', () {
    for (final reason in [
      'bad-txns-duplicate-nullifier-requirements-not-met',
      'bad-txns-sapling-duplicate-nullifier',
      'bad-txns-ironwood-duplicate-nullifier',
      'mempool conflict',
    ]) {
      final error = TransactionErrorMapper.mapError(
        'Network error: Broadcast failed: 16: $reason (code -26)',
      );
      expect(error.type, TransactionErrorType.txConflict, reason: reason);
      expect(error.technicalDetails, contains(reason));
    }
  });

  test('malformed duplicate inputs and proofs are rejected, not sent', () {
    for (final reason in [
      'bad-spend-description-nullifiers-duplicate',
      'bad-ironwood-nullifiers-duplicate',
      'bad-txns-inputs-duplicate',
      'duplicate proof',
    ]) {
      expect(
        TransactionErrorMapper.mapError('Broadcast failed: $reason').type,
        TransactionErrorType.txRejected,
        reason: reason,
      );
    }
    expect(
      TransactionErrorMapper.mapError('duplicate database entry').type,
      isNot(TransactionErrorType.txAlreadyInMempool),
    );
  });

  test(
    'exact known-transaction responses and expiry survive network wrapping',
    () {
      for (final reason in [
        'already in mempool',
        'txn-already-in-mempool',
        'transaction already in block chain',
      ]) {
        expect(
          TransactionErrorMapper.mapError('Network error: $reason').type,
          TransactionErrorType.txAlreadyInMempool,
        );
      }
      expect(
        TransactionErrorMapper.mapError('Network error: tx-expired').type,
        TransactionErrorType.txExpired,
      );
      expect(
        TransactionErrorMapper.mapError('connection timeout').type,
        TransactionErrorType.networkError,
      );
    },
  );
}
