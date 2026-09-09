import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/ffi/generated/frb_generated.dart';
import 'package:pirate_wallet/core/ffi/generated/models.dart';
import 'package:pirate_wallet/core/security/viewing_key_export.dart';

import '../../support/restored_wallet_api.dart';

class _ExportApi extends RestoredWalletApi {
  String current = 'zs1accounttwo';
  int? exportedId;
  bool missingKey = false;

  @override
  Future<String> crateApiCurrentReceiveAddress({
    required String walletId,
  }) async => current;

  @override
  Future<KeyExportInfo> crateApiExportKeyGroupKeys({
    required String walletId,
    required int keyId,
  }) async {
    exportedId = keyId;
    return KeyExportInfo(
      keyId: keyId,
      saplingViewingKey: missingKey ? null : 'zxviews1account$keyId',
      ironwoodViewingKey: missingKey
          ? null
          : 'pirate-extended-viewing-key1account$keyId',
    );
  }
}

void main() {
  late _ExportApi api;
  setUp(() {
    api = _ExportApi()..addresses[2] = 'zs1accounttwo';
    RustLib.initMock(api: api);
  });
  tearDown(RustLib.dispose);

  test(
    'exports Sapling from the selected account, not the primary account',
    () async {
      expect(
        await exportCurrentAddressViewingKey('wallet'),
        'zxviews1account2',
      );
      expect(api.exportedId, 2);
    },
  );

  for (final prefix in ['pirate1', 'pirate-test1', 'pirate-regtest1']) {
    test('exports Ironwood for $prefix', () async {
      api.current = '${prefix}accounttwo';
      api.addresses[2] = api.current;
      expect(
        await exportCurrentAddressViewingKey('wallet'),
        'pirate-extended-viewing-key1account2',
      );
      expect(api.exportedId, 2);
    });
  }

  test(
    'does not fall back to another account or pool when unavailable',
    () async {
      api.current = 'zs1unknown';
      await expectLater(
        exportCurrentAddressViewingKey('wallet'),
        throwsStateError,
      );
      expect(api.exportedId, isNull);
      api.current = 'zs1accounttwo';
      api.missingKey = true;
      await expectLater(
        exportCurrentAddressViewingKey('wallet'),
        throwsStateError,
      );
    },
  );
}
