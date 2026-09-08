import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/formatting/arrr_amount.dart';

void main() {
  test('never rounds a small payment to zero', () {
    expect(formatArrrAtomic(BigInt.one), '0.00000001');
    expect(formatArrrAtomic(-BigInt.one), '-0.00000001');
    expect(formatArrrAtomic(BigInt.from(123456789)), '1.23456789');
    expect(formatArrrAtomic(BigInt.from(123450000)), '1.2345');
  });
  test('keeps exact atomic units beyond double integer precision', () {
    expect(
      formatArrrAtomic(BigInt.parse('19999999999999999'), groupThousands: true),
      '199,999,999.99999999',
    );
  });
  test('preserves the wallet display conventions', () {
    expect(formatArrrAtomic(BigInt.zero, showPositiveSign: true), '+0.0000');
    expect(
      formatArrrAtomic(BigInt.from(100000000), minimumFractionDigits: 8),
      '1.00000000',
    );
    expect(
      formatArrrAtomic(BigInt.from(100000000), minimumFractionDigits: 0),
      '1',
    );
  });
}
