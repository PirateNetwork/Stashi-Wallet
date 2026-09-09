import '../ffi/ffi_bridge.dart';
import '../i18n/arb_text_localizer.dart';

/// Export only the viewing key matching the current receive address and account.
Future<String> exportCurrentAddressViewingKey(String walletId) async {
  final address = await FfiBridge.currentReceiveAddress(walletId);
  final addresses = await FfiBridge.listAddressBalances(walletId);
  final account = addresses
      .where((item) => item.address == address)
      .firstOrNull;
  final keyId = account?.keyId;
  if (keyId == null) throw StateError('Address not found'.tr);
  final isIronwood =
      address.startsWith('pirate1') ||
      address.startsWith('pirate-test1') ||
      address.startsWith('pirate-regtest1');
  final exported = await FfiBridge.exportKeyGroupKeys(
    walletId: walletId,
    keyId: keyId,
  );
  final ivk = isIronwood
      ? exported.ironwoodViewingKey
      : exported.saplingViewingKey;
  if (ivk == null || ivk.isEmpty) {
    throw StateError('Viewing key unavailable'.tr);
  }
  return ivk;
}
