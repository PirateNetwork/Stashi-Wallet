import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/ffi/ffi_bridge.dart';
import 'package:pirate_wallet/features/settings/providers/endpoint_health_provider.dart';

NodeTestResult result({required bool success, String chain = 'main'}) =>
    NodeTestResult(
      success: success,
      latestBlockHeight: success ? 4100000 : null,
      transportMode: 'direct',
      tlsEnabled: true,
      responseTimeMs: 10,
      chainName: chain,
      errorMessage: success ? null : 'HTTP 502 Bad Gateway',
    );

void main() {
  test('Auto test succeeds when the primary returns a gateway error', () async {
    final tested = await testEndpointSelection(
      config: const LightdEndpointConfig(
        url: 'https://lightwalletd2.cryptoforge.cc:443',
        automaticFailover: true,
      ),
      probe: ({required url, tlsPin}) async =>
          result(success: url == 'https://lightwalletd1.cryptoforge.cc:443'),
      timeout: const Duration(seconds: 1),
    );
    expect(tested.result.success, isTrue);
    expect(tested.url, 'https://lightwalletd1.cryptoforge.cc:443');
  });

  test('Pinned selection never tests an alternate server', () async {
    final urls = <String>[];
    final tested = await testEndpointSelection(
      config: const LightdEndpointConfig(
        url: 'https://lightwalletd2.cryptoforge.cc:443',
        automaticFailover: true,
        tlsPin: 'expected-pin',
      ),
      probe: ({required url, tlsPin}) async {
        urls.add(url);
        expect(tlsPin, 'expected-pin');
        return result(success: false);
      },
      timeout: const Duration(seconds: 1),
    );
    expect(urls, hasLength(1));
    expect(tested.result.success, isFalse);
  });

  test('Auto does not accept a server on the wrong chain', () async {
    final tested = await testEndpointSelection(
      config: const LightdEndpointConfig(
        url: 'https://lightwalletd2.cryptoforge.cc:443',
        automaticFailover: true,
      ),
      probe: ({required url, tlsPin}) async =>
          result(success: true, chain: 'test'),
      timeout: const Duration(seconds: 1),
    );
    expect(tested.result.success, isFalse);
    expect(tested.result.errorMessage, contains('unexpected chain'));
  });
}
