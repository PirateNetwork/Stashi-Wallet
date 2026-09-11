import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ffi/ffi_bridge.dart';
import '../../core/ffi/generated/models.dart';
import '../../core/providers/wallet_providers.dart';

typedef DisclosureRequest = ({WalletId walletId, String txid});

/// Share in-flight work while the screen is open. The native wallet database
/// retains successful disclosures across screen closes and app restarts.
/// Session changes dispose the old results, including pending requests.
final paymentDisclosuresProvider = FutureProvider.autoDispose
    .family<List<PaymentDisclosure>, DisclosureRequest>((ref, request) async {
      final unlocked = ref.watch(appUnlockedProvider);
      final activeWallet = ref.watch(activeWalletProvider);
      if (!unlocked || activeWallet != request.walletId) return const [];

      return FfiBridge.exportPaymentDisclosures(
        walletId: request.walletId,
        txid: request.txid,
      );
    }, retry: (_, _) => null);
