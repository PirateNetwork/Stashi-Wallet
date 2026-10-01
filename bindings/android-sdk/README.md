# Pirate Wallet Android SDK

This directory contains the Android wrapper and packaging inputs.

Canonical docs:

- [Android SDK overview](../../docs/native-sdk-android.md)
- [Android SDK API reference](../../docs/native-sdk-android-api.md)

The SDK uses Direct networking and omits embedded Tor and I2P. The default SDK
embeds Sapling proving parameters. The optional
`pirate-android-sdk-external-release.aar` uses host-provided proving files; see
the overview for parameter initialization before signing and network privacy
responsibilities.
