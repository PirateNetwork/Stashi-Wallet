# Pirate Wallet iOS SDK

This directory contains the Swift wrapper and package layout.

Canonical docs:

- [iOS SDK overview](../../docs/native-sdk-ios.md)
- [iOS SDK API reference](../../docs/native-sdk-ios-api.md)

The SDK uses Direct networking and omits embedded Tor and I2P. Default binary
packages embed Sapling proving parameters. The consuming app owns its networking
and privacy policy; Stashi enables its privacy transports in a separate build.
