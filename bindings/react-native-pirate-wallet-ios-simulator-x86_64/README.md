# react-native-pirate-wallet-ios-simulator-x86_64

This package contains the x86_64 iOS simulator native library used by
`react-native-pirate-wallet`.

The library uses Direct networking, omits embedded Tor and I2P, and embeds
Sapling proving parameters. The consuming app owns its network privacy policy.

Applications should depend on `react-native-pirate-wallet`. On macOS, its
CocoaPods integration combines this package with the arm64 simulator package
into the universal simulator slice expected by Xcode.
