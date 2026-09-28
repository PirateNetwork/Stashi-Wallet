import 'dart:ffi' show Abi;

import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/services/desktop_update_service.dart';

void main() {
  group('Linux release architecture', () {
    DesktopReleaseAsset asset(String name) => DesktopReleaseAsset(
      name: name,
      downloadUrl: 'https://example.invalid/$name',
    );

    test('selects the matching Debian package from a mixed release', () {
      final assets = [
        asset('Stashi-Wallet-amd64.deb'),
        asset('Stashi-Wallet-arm64.deb'),
      ];
      expect(
        DesktopUpdateService.selectLinuxAssetForTesting(
          assets,
          abi: Abi.linuxX64,
        )?.asset.name,
        'Stashi-Wallet-amd64.deb',
      );
      expect(
        DesktopUpdateService.selectLinuxAssetForTesting(
          assets,
          abi: Abi.linuxArm64,
        )?.asset.name,
        'Stashi-Wallet-arm64.deb',
      );
    });

    test('never falls back to the other CPU or an ambiguous name', () {
      for (final name in [
        'Stashi-Wallet-amd64.deb',
        'Stashi-Wallet-linux-x86_64.AppImage',
        'Stashi-Wallet.flatpak',
        'Stashi-Wallet-arm64-amd64.deb',
      ]) {
        expect(
          DesktopUpdateService.selectLinuxAssetForTesting([
            asset(name),
          ], abi: Abi.linuxArm64),
          isNull,
          reason: name,
        );
      }
      expect(
        DesktopUpdateService.selectLinuxAssetForTesting([
          asset('Stashi-Wallet-arm64.deb'),
        ], abi: Abi.linuxX64),
        isNull,
      );
      expect(
        DesktopUpdateService.selectLinuxAssetForTesting([
          asset('Stashi-Wallet-arm64.deb'),
        ], abi: Abi.linuxArm),
        isNull,
      );
    });

    test('recognizes ARM64 and x64 names in all Linux formats', () {
      final cases = [
        (
          'Stashi-Wallet-aarch64.AppImage',
          Abi.linuxArm64,
          DesktopUpdateAssetKind.linuxAppImage,
        ),
        (
          'Stashi-Wallet-arm64.flatpak',
          Abi.linuxArm64,
          DesktopUpdateAssetKind.linuxFlatpak,
        ),
        (
          'Stashi-Wallet-x86_64.AppImage',
          Abi.linuxX64,
          DesktopUpdateAssetKind.linuxAppImage,
        ),
        (
          'Stashi-Wallet-x86_64.flatpak',
          Abi.linuxX64,
          DesktopUpdateAssetKind.linuxFlatpak,
        ),
        (
          'Stashi-Wallet.flatpak',
          Abi.linuxX64,
          DesktopUpdateAssetKind.linuxFlatpak,
        ),
      ];
      for (final (name, abi, kind) in cases) {
        final selected = DesktopUpdateService.selectLinuxAssetForTesting([
          asset(name),
        ], abi: abi);
        expect(selected?.asset.name, name);
        expect(selected?.kind, kind);
      }
    });

    test('skips newer releases with no compatible Linux artifact', () {
      final now = DateTime.utc(2026, 9, 28);
      DesktopReleaseInfo release(
        String tag,
        List<DesktopReleaseAsset> assets,
      ) => DesktopReleaseInfo(
        tagName: tag,
        name: tag,
        releaseUrl: '',
        publishedAt: now.subtract(const Duration(days: 1)),
        isDraft: false,
        isPrerelease: false,
        assets: assets,
      );
      final selected = DesktopUpdateService.newestEligibleRelease(
        [
          release('v1.2.6', [asset('Stashi-Wallet-amd64.deb')]),
          release('v1.2.5', [asset('Stashi-Wallet-arm64.deb')]),
        ],
        now,
        supportsAssets: (assets) =>
            DesktopUpdateService.selectLinuxAssetForTesting(
              assets,
              abi: Abi.linuxArm64,
            ) !=
            null,
      );
      expect(selected?.tagName, 'v1.2.5');
    });
  });

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
