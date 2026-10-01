# react-native-pirate-wallet-ios-device

`react-native-pirate-wallet-ios-device` contains the iOS device XCFramework
slice used by `react-native-pirate-wallet`.

The library uses Direct networking, omits embedded Tor and I2P, and embeds
Sapling proving parameters. The consuming app owns its network privacy policy.

Applications should depend on `react-native-pirate-wallet`. The wrapper
installs this package automatically on macOS.
