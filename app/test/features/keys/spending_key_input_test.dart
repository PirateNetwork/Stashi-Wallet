import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/features/keys/spending_key_input.dart';

void main() {
  // These payloads are routing fixtures, not valid cryptographic keys. Native
  // import remains responsible for checksums and key-material validation.
  for (final prefix in [
    'secret-extended-key-main',
    'secret-extended-key-test',
    'secret-extended-key-regtest',
  ]) {
    test('routes $prefix to Sapling', () {
      final key =
          '$prefix'
          '1qqqq';
      final parsed = SpendingKeyInput.parse(' \n$key\t');
      expect(parsed.sapling, key);
      expect(parsed.ironwood, isNull);
    });
  }
  for (final prefix in [
    'pirate-secret-extended-key',
    'pirate-secret-extended-key-test',
    'pirate-secret-extended-key-regtest',
  ]) {
    test('routes $prefix to Ironwood', () {
      final key =
          '$prefix'
          '1qqqq';
      final parsed = SpendingKeyInput.parse(key.toUpperCase());
      expect(parsed.ironwood, key);
      expect(parsed.sapling, isNull);
    });
  }
  test('preserves a pair regardless of order or whitespace', () {
    const sapling = 'secret-extended-key-main1qqqq';
    const ironwood = 'pirate-secret-extended-key1qqqq';
    for (final input in ['$sapling $ironwood', '$ironwood\n\t$sapling']) {
      final parsed = SpendingKeyInput.parse(input);
      expect(parsed.sapling, sapling);
      expect(parsed.ironwood, ironwood);
    }
  });
  test('rejects unsupported formats without exposing input', () {
    for (final input in [
      '',
      'zs1address',
      'zxviews1viewingkey',
      'secret-extended-key-main1',
      'secret-extended-key-main1qQqQ',
      'secret-extended-key-mainnet1qqqq',
    ]) {
      try {
        SpendingKeyInput.parse(input);
        fail('Input should be rejected');
      } on SpendingKeyInputException catch (error) {
        if (input.isNotEmpty) expect(error.toString(), isNot(contains(input)));
      }
    }
  });
  test('rejects duplicate pools and extra keys instead of discarding them', () {
    const key = 'secret-extended-key-main1qqqq';
    expect(
      () => SpendingKeyInput.parse('$key $key'),
      throwsA(
        isA<SpendingKeyInputException>().having(
          (e) => e.reason,
          'reason',
          SpendingKeyInputError.duplicate,
        ),
      ),
    );
    expect(
      () => SpendingKeyInput.parse('$key $key $key'),
      throwsA(
        isA<SpendingKeyInputException>().having(
          (e) => e.reason,
          'reason',
          SpendingKeyInputError.tooMany,
        ),
      ),
    );
  });
}
