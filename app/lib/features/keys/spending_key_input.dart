/// Identifies the native spending-key encodings without duplicating the native
/// checksum, key-material or wallet-network validation. Never log these values.
class SpendingKeyInput {
  const SpendingKeyInput._({this.sapling, this.ironwood});

  final String? sapling;
  final String? ironwood;

  factory SpendingKeyInput.parse(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      throw const SpendingKeyInputException(SpendingKeyInputError.empty);
    }
    final keys = text.split(RegExp(r'\s+'));
    if (keys.length > 2) {
      throw const SpendingKeyInputException(SpendingKeyInputError.tooMany);
    }
    String? sapling;
    String? ironwood;
    for (final raw in keys) {
      // Bech32 allows either case, but never mixed case. Only normalize an
      // entirely uppercase key; silently repairing mixed case hides mistakes.
      if (raw != raw.toLowerCase() && raw != raw.toUpperCase()) {
        throw const SpendingKeyInputException(SpendingKeyInputError.format);
      }
      final key = raw.toLowerCase();
      final separator = key.lastIndexOf('1');
      if (separator <= 0 || separator == key.length - 1) {
        throw const SpendingKeyInputException(SpendingKeyInputError.format);
      }
      final prefix = key.substring(0, separator);
      switch (prefix) {
        case 'secret-extended-key-main':
        case 'secret-extended-key-test':
        case 'secret-extended-key-regtest':
          if (sapling != null) {
            throw const SpendingKeyInputException(
              SpendingKeyInputError.duplicate,
            );
          }
          sapling = key;
        case 'pirate-secret-extended-key':
        case 'pirate-secret-extended-key-test':
        case 'pirate-secret-extended-key-regtest':
          if (ironwood != null) {
            throw const SpendingKeyInputException(
              SpendingKeyInputError.duplicate,
            );
          }
          ironwood = key;
        default:
          throw const SpendingKeyInputException(SpendingKeyInputError.format);
      }
    }
    return SpendingKeyInput._(sapling: sapling, ironwood: ironwood);
  }
}

enum SpendingKeyInputError { empty, format, duplicate, tooMany }

class SpendingKeyInputException implements Exception {
  const SpendingKeyInputException(this.reason);

  final SpendingKeyInputError reason;

  // Deliberately excludes the input, including from exception diagnostics.
  @override
  String toString() => 'SpendingKeyInputException(${reason.name})';
}
