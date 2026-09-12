import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/services/desktop_update_service.dart';

void main() {
  group('official release asset URLs', () {
    const path = '/releases/download/v1.2.2/installer.exe';
    const current = 'https://github.com/PirateNetwork/Stashi-Wallet';

    test('accepts current and legacy repository downloads', () {
      for (final repository in [
        'Stashi-Wallet',
        'Pirate-Unified-Light-Wallet',
      ]) {
        expect(
          DesktopUpdateService.isOfficialReleaseAssetUrl(
            'https://github.com/PirateNetwork/$repository$path',
            tagName: 'v1.2.2',
            assetName: 'installer.exe',
          ),
          isTrue,
        );
      }
    });

    test('rejects spoofed origins, paths, tags and filenames', () {
      for (final url in [
        'http://github.com/PirateNetwork/Stashi-Wallet$path',
        'https://github.com.evil.example/PirateNetwork/Stashi-Wallet$path',
        'https://github.com@evil.example/PirateNetwork/Stashi-Wallet$path',
        'https://github.com/OtherOwner/Stashi-Wallet$path',
        'https://github.com/PirateNetwork/OtherRepository$path',
        '$current/releases/download/v1.2.1/installer.exe',
        '$current/releases/download/v1.2.2/other.exe',
        '$current/releases/latest/download/installer.exe',
        '$current$path?download=1',
        '$current$path#fragment',
        '$current/releases/download/v1.2.2/../installer.exe',
      ]) {
        expect(
          DesktopUpdateService.isOfficialReleaseAssetUrl(
            url,
            tagName: 'v1.2.2',
            assetName: 'installer.exe',
          ),
          isFalse,
          reason: url,
        );
      }
    });

    test('rejects traversal even when it matches supplied metadata', () {
      for (final pair in [
        ['v1.2.2/..', 'installer.exe'],
        ['v1.2.2', '../installer.exe'],
      ]) {
        expect(
          DesktopUpdateService.isOfficialReleaseAssetUrl(
            '$current/releases/download/${pair[0]}/${pair[1]}',
            tagName: pair[0],
            assetName: pair[1],
          ),
          isFalse,
        );
      }
    });
  });

  test('semantic versions order stable, numeric prereleases and metadata', () {
    for (final pair in [
      ['v1.2.1', '1.2.0'],
      ['1.10.0', '1.9.9'],
      ['1.2.1', '1.2.1-rc.2'],
      ['1.2.1-rc.10', '1.2.1-rc.2'],
      ['1.2.1-beta', '1.2.1-alpha'],
    ]) {
      expect(
        DesktopUpdateService.compareVersions(pair[0], pair[1]),
        greaterThan(0),
      );
      expect(
        DesktopUpdateService.compareVersions(pair[1], pair[0]),
        lessThan(0),
      );
    }
    expect(DesktopUpdateService.compareVersions('v1.2.1+10201', '1.2.1'), 0);
  });
  test(
    'selects newest supported stable release after publication quarantine',
    () {
      final now = DateTime.utc(2026, 9, 5);
      DesktopReleaseInfo release(
        String version, {
        bool supported = true,
        bool draft = false,
        Duration age = const Duration(days: 1),
      }) => DesktopReleaseInfo(
        tagName: version,
        name: version,
        releaseUrl: '',
        publishedAt: now.subtract(age),
        isDraft: draft,
        isPrerelease: false,
        assets: supported
            ? [
                const DesktopReleaseAsset(
                  name: 'installer.exe',
                  downloadUrl: '',
                ),
              ]
            : [],
      );
      final result = DesktopUpdateService.newestEligibleRelease(
        [
          release('v1.2.0'),
          release('v1.4.0', supported: false),
          release('v1.2.2', age: const Duration(minutes: 10)),
          release('v1.2.1'),
          release('v1.3.0', draft: true),
          release('v2.0.0-rc.1'),
        ],
        now,
        supportsAssets: (assets) => assets.isNotEmpty,
      );
      expect(result?.tagName, 'v1.2.1');
    },
  );
}
