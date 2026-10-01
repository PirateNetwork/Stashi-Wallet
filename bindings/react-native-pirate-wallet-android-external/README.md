# react-native-pirate-wallet-android-external

Opt-in compact Android native libraries without embedded Tor, I2P, or Sapling
proving parameters.
Includes ARM64, ARMv7, and x86_64. Install the same exact version as
`react-native-pirate-wallet`, then set this in `android/gradle.properties`:

```properties
pirateWalletAndroidBinaryPackage=react-native-pirate-wallet-android-external
```

This selects only these native libraries, even if the normal embedded binary
packages are installed. Before testing endpoints or starting sync, configure
account storage and explicitly select the host's SOCKS5 proxy:

```js
await sdk.setTunnel({ mode: 'socks5', url: 'socks5h://127.0.0.1:9050' })
```

The host starts and maintains that proxy. Using `socks5h` delegates hostname
resolution to it. If the host intentionally allows a direct connection, select
`await sdk.setTunnel({ mode: 'direct' })`; Direct exposes the device's IP address
to the server and DNS provider. There is no automatic fallback to Direct.
Selecting `tor` or `i2p` rejects with a transport-unavailable error because those
embedded transports are omitted. Standard Android companions keep both.

The host must configure verified Sapling parameter files
before signing any transaction, including Ironwood-only transactions, because
the shared builder loads the Sapling prover. Receiving and syncing do not require
these files. See the wrapper's parameter setup API in its README. The native SDK
does not download files. See the wrapper README for the complete setup flow.
