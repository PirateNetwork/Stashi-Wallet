/// Formats atomic ARRR without a floating-point round trip. Four fractional
/// places are kept by default, extending to eight whenever value would be lost.
String formatArrrAtomic(
  BigInt atomic, {
  int minimumFractionDigits = 4,
  bool groupThousands = false,
  bool showPositiveSign = false,
}) {
  assert(
    minimumFractionDigits >= 0 && minimumFractionDigits <= 8,
    'ARRR supports zero through eight fractional digits',
  );
  final magnitude = atomic.abs();
  final unit = BigInt.from(100000000);
  var whole = (magnitude ~/ unit).toString();
  if (groupThousands) {
    whole = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }
  var fraction = (magnitude % unit).toString().padLeft(8, '0');
  while (fraction.length > minimumFractionDigits && fraction.endsWith('0')) {
    fraction = fraction.substring(0, fraction.length - 1);
  }
  final sign = atomic.isNegative
      ? '-'
      : showPositiveSign
      ? '+'
      : '';
  return '$sign$whole${fraction.isEmpty ? '' : '.$fraction'}';
}
