# react-native-pirate-wallet-android

`react-native-pirate-wallet-android` contains the Android ARM native libraries
used by `react-native-pirate-wallet`.

The library uses Direct networking, omits embedded Tor and I2P, and embeds
Sapling proving parameters. The consuming app owns its network privacy policy.

Applications should depend on `react-native-pirate-wallet`. The wrapper
installs this package automatically and adds its libraries to Android builds.
