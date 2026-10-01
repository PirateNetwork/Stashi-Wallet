# Pirate Wallet Android SDK

This directory contains the Android wrapper and packaging inputs.

Canonical docs:

- [Android SDK overview](../../docs/native-sdk-android.md)
- [Android SDK API reference](../../docs/native-sdk-android-api.md)

The default SDK embeds Tor, I2P, and Sapling proving parameters. The optional
`pirate-android-sdk-external-release.aar` omits all three and uses explicit
host-managed SOCKS5 or Direct networking and host-provided proving files. See
the overview for transport setup and parameter initialization before signing.
