# react-native-pirate-wallet-android-external

Opt-in compact Android native libraries without embedded Tor, I2P, or Sapling
proving parameters.
Includes ARM64, ARMv7, and x86_64. Install the same exact version as
`react-native-pirate-wallet`, then set this in `android/gradle.properties`:

```properties
pirateWalletAndroidBinaryPackage=react-native-pirate-wallet-android-external
```

This selects only these native libraries, even if the normal binary packages
are installed. Both variants use Direct networking and omit embedded Tor and
I2P; this package additionally omits the Sapling proving files. Direct
connections expose the device's IP address to the server and DNS provider. The
consuming app owns its network and privacy policy. Tor/I2P integration belongs
to Stashi's separate build.

The host must configure verified Sapling parameter files
before signing any transaction, including Ironwood-only transactions, because
the shared builder loads the Sapling prover. Receiving and syncing do not require
these files. See the wrapper's parameter setup API in its README. The native SDK
does not download files. See the wrapper README for the complete setup flow.
