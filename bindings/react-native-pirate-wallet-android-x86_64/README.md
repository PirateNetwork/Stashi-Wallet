# react-native-pirate-wallet-android-x86_64

`react-native-pirate-wallet-android-x86_64` contains the Android x86_64
emulator library used by `react-native-pirate-wallet`.

The library uses Direct networking, omits embedded Tor and I2P, and embeds
Sapling proving parameters. The consuming app owns its network privacy policy.

Applications should depend on `react-native-pirate-wallet`. The wrapper
installs this package automatically and adds its library to Android builds.
