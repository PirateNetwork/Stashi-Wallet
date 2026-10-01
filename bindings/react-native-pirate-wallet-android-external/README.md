# react-native-pirate-wallet-android-external

Opt-in Android native libraries without embedded Sapling proving parameters.
Includes ARM64, ARMv7, and x86_64. Install the same exact version as
`react-native-pirate-wallet`, then set this in `android/gradle.properties`:

```properties
pirateWalletAndroidBinaryPackage=react-native-pirate-wallet-android-external
```

This selects only these native libraries, even if the normal embedded binary
packages are installed. The host must configure verified Sapling parameter files
before signing any transaction, including Ironwood-only transactions, because
the shared builder loads the Sapling prover. Receiving and syncing do not require
these files. See the wrapper's parameter setup API in its README. The native SDK
does not download files or choose a network transport.
