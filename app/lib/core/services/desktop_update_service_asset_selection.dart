part of 'desktop_update_service.dart';

class _DesktopUpdateAssetSelectionHelper {
  ({DesktopReleaseAsset asset, DesktopUpdateAssetKind kind})? selectBestAsset(
    List<DesktopReleaseAsset> assets,
  ) {
    if (assets.isEmpty) {
      return null;
    }

    DesktopReleaseAsset? prefer(
      bool Function(DesktopReleaseAsset asset) predicate, {
      bool signedOnly = false,
    }) {
      for (final asset in assets) {
        if (!predicate(asset)) {
          continue;
        }
        if (signedOnly && isUnsignedAsset(asset.name)) {
          continue;
        }
        if (!isUnsignedAsset(asset.name)) {
          return asset;
        }
      }
      if (signedOnly) {
        return null;
      }
      for (final asset in assets) {
        if (predicate(asset)) {
          return asset;
        }
      }
      return null;
    }

    if (Platform.isWindows) {
      final installer =
          prefer(_isWindowsInstallerAsset, signedOnly: true) ??
          prefer(_isWindowsInstallerAsset) ??
          prefer(_isWindowsExecutableAsset, signedOnly: true) ??
          prefer(_isWindowsExecutableAsset);
      if (installer != null) {
        return (
          asset: installer,
          kind: DesktopUpdateAssetKind.windowsInstaller,
        );
      }
      final portable = prefer(_isWindowsPortableAsset);
      if (portable != null) {
        return (
          asset: portable,
          kind: DesktopUpdateAssetKind.windowsPortableZip,
        );
      }
      return null;
    }

    if (Platform.isLinux) {
      return selectLinuxAsset(
        assets,
        abi: Abi.current(),
        installMode: _detectLinuxInstallMode(),
      );
    }

    if (Platform.isMacOS) {
      final dmg =
          prefer(_isMacDmgAsset, signedOnly: true) ?? prefer(_isMacDmgAsset);
      if (dmg != null) {
        return (asset: dmg, kind: DesktopUpdateAssetKind.macDmg);
      }
      return null;
    }

    return null;
  }

  ({DesktopReleaseAsset asset, DesktopUpdateAssetKind kind})? selectLinuxAsset(
    List<DesktopReleaseAsset> assets, {
    required Abi abi,
    required _LinuxInstallMode installMode,
  }) {
    // Never offer a binary from another CPU family. In particular, the legacy
    // architecture-neutral Flatpak filename was only ever built for x86-64.
    if (abi != Abi.linuxX64 && abi != Abi.linuxArm64) return null;

    DesktopReleaseAsset? preferLinux(
      bool Function(DesktopReleaseAsset asset) format,
    ) {
      for (final asset in assets) {
        if (format(asset) &&
            _matchesLinuxArchitecture(asset.name, abi) &&
            !isUnsignedAsset(asset.name)) {
          return asset;
        }
      }
      for (final asset in assets) {
        if (format(asset) && _matchesLinuxArchitecture(asset.name, abi)) {
          return asset;
        }
      }
      return null;
    }

    final appImage = preferLinux(_isLinuxAppImageAsset);
    final deb = preferLinux(_isLinuxDebAsset);
    final flatpak = preferLinux(_isLinuxFlatpakAsset);
    switch (installMode) {
      case _LinuxInstallMode.appImage:
        if (appImage != null) {
          return (asset: appImage, kind: DesktopUpdateAssetKind.linuxAppImage);
        }
        if (deb != null) {
          return (asset: deb, kind: DesktopUpdateAssetKind.linuxDeb);
        }
        if (flatpak != null) {
          return (asset: flatpak, kind: DesktopUpdateAssetKind.linuxFlatpak);
        }
        return null;
      case _LinuxInstallMode.flatpak:
        if (flatpak != null) {
          return (asset: flatpak, kind: DesktopUpdateAssetKind.linuxFlatpak);
        }
        if (deb != null) {
          return (asset: deb, kind: DesktopUpdateAssetKind.linuxDeb);
        }
        if (appImage != null) {
          return (asset: appImage, kind: DesktopUpdateAssetKind.linuxAppImage);
        }
        return null;
      case _LinuxInstallMode.systemPackage:
        if (deb != null) {
          return (asset: deb, kind: DesktopUpdateAssetKind.linuxDeb);
        }
        if (flatpak != null) {
          return (asset: flatpak, kind: DesktopUpdateAssetKind.linuxFlatpak);
        }
        if (appImage != null) {
          return (asset: appImage, kind: DesktopUpdateAssetKind.linuxAppImage);
        }
        return null;
      case _LinuxInstallMode.unknown:
        if (deb != null) {
          return (asset: deb, kind: DesktopUpdateAssetKind.linuxDeb);
        }
        if (appImage != null) {
          return (asset: appImage, kind: DesktopUpdateAssetKind.linuxAppImage);
        }
        if (flatpak != null) {
          return (asset: flatpak, kind: DesktopUpdateAssetKind.linuxFlatpak);
        }
        return null;
    }
  }

  bool _matchesLinuxArchitecture(String name, Abi abi) {
    final lower = name.toLowerCase();
    final x64 = RegExp(r'(^|[._-])(amd64|x86_64|x64)(?=[._-]|$)')
        .hasMatch(lower);
    final arm64 = RegExp(r'(^|[._-])(arm64|aarch64)(?=[._-]|$)')
        .hasMatch(lower);
    if (x64 && arm64) return false;
    if (abi == Abi.linuxArm64) return arm64;
    if (abi == Abi.linuxX64) {
      return x64 || lower == 'stashi-wallet.flatpak';
    }
    return false;
  }

  bool isUnsignedAsset(String name) {
    return name.toLowerCase().contains('unsigned');
  }

  bool _isWindowsInstallerAsset(DesktopReleaseAsset asset) {
    final lower = asset.name.toLowerCase();
    return lower.endsWith('.exe') &&
        (lower.contains('installer') || lower.contains('setup'));
  }

  bool _isWindowsPortableAsset(DesktopReleaseAsset asset) {
    final lower = asset.name.toLowerCase();
    return lower.endsWith('.zip') && lower.contains('portable');
  }

  bool _isWindowsExecutableAsset(DesktopReleaseAsset asset) {
    final lower = asset.name.toLowerCase();
    return lower.endsWith('.exe') && !lower.contains('portable');
  }

  bool _isLinuxAppImageAsset(DesktopReleaseAsset asset) {
    return asset.name.toLowerCase().endsWith('.appimage');
  }

  bool _isLinuxDebAsset(DesktopReleaseAsset asset) {
    return asset.name.toLowerCase().endsWith('.deb');
  }

  bool _isLinuxFlatpakAsset(DesktopReleaseAsset asset) {
    return asset.name.toLowerCase().endsWith('.flatpak');
  }

  bool _isMacDmgAsset(DesktopReleaseAsset asset) {
    return asset.name.toLowerCase().endsWith('.dmg');
  }

  _LinuxInstallMode _detectLinuxInstallMode() {
    final env = Platform.environment;
    final executable = Platform.resolvedExecutable;
    if (env.containsKey('FLATPAK_ID') || executable.startsWith('/app/')) {
      return _LinuxInstallMode.flatpak;
    }
    final appImage = env['APPIMAGE'];
    if (appImage != null && appImage.isNotEmpty) {
      return _LinuxInstallMode.appImage;
    }
    if (executable.toLowerCase().endsWith('.appimage')) {
      return _LinuxInstallMode.appImage;
    }
    if (executable.startsWith('/usr/') || executable.startsWith('/opt/')) {
      return _LinuxInstallMode.systemPackage;
    }
    return _LinuxInstallMode.unknown;
  }

  String? resolveLinuxAppImagePath() {
    final envPath = Platform.environment['APPIMAGE'];
    if (envPath != null && envPath.isNotEmpty) {
      return envPath;
    }
    final executable = Platform.resolvedExecutable;
    if (executable.toLowerCase().endsWith('.appimage')) {
      return executable;
    }
    return null;
  }
}
