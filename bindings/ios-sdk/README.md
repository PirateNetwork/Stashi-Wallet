# Pirate Wallet iOS SDK

This directory contains the Swift wrapper and package layout.

Canonical docs:

- [iOS SDK overview](../../docs/native-sdk-ios.md)
- [iOS SDK API reference](../../docs/native-sdk-ios-api.md)

Default binary packages embed Tor, I2P, and Sapling proving parameters. Source
consumers can run `bash scripts/build-ios-sdk.sh --no-embedded-transports` to
produce an isolated SDK under `dist/ios-sdk-host-network/`; explicitly configure
host-managed SOCKS5 or Direct before connecting.
