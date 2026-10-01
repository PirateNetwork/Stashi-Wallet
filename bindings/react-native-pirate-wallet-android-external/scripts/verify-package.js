'use strict';

const fs = require('fs');
const path = require('path');

const expectedName = 'react-native-pirate-wallet-android-external';
const packageRoot = path.resolve(__dirname, '..');
// 64-byte public-parameter sequences at offset 4096 in the canonical files.
// Detect parameter blobs accidentally linked through Cargo feature unification.
const parameterSentinels = [
  'c87e58906a996bb89bcb515f71408b6b79d0498511dfa90e23aec6b7cf1124f7c' +
    'cf2c50faf3ba66c136be6c30c2ff68039fafde5fc7b87ad2e9465e060b1a57e',
  'c45759dde3ee8bcb3076ab4ea9b1324162005c041fe5113c20ad69e15b9871f6' +
    '4053632d3d9bd50f0851718b02ff6ba34d3fb8614e315b5456a17aba4aa0819d',
].map(value => Buffer.from(value, 'hex'));
const maxLibraryBytes = 50_000_000;

function verifyNativeLibrary(libraryPath, abi) {
  const stat = fs.statSync(libraryPath, {throwIfNoEntry: false});
  if (!stat?.isFile() || stat.size === 0) {
    throw new Error(`Missing or empty native library: ${libraryPath}`);
  }
  if (stat.size > maxLibraryBytes) {
    throw new Error(`${abi} native library exceeds the ${maxLibraryBytes}-byte size budget: ${stat.size}`);
  }
  const bytes = fs.readFileSync(libraryPath);
  if (!bytes.subarray(0, 4).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]))) {
    throw new Error(`${abi} native library is not ELF`);
  }
  const expectedMachine = {'arm64-v8a': 183, 'armeabi-v7a': 40, x86_64: 62}[abi];
  const expectedClass = abi === 'armeabi-v7a' ? 1 : 2;
  if (bytes.length < 20 || bytes[4] !== expectedClass || bytes[5] !== 1 ||
      bytes.readUInt16LE(18) !== expectedMachine) {
    throw new Error(`${abi} native library has the wrong ELF architecture`);
  }
  if (bytes.readUInt16LE(16) !== 3) {
    throw new Error(`${abi} native library is not an ELF shared object`);
  }
  for (const symbol of [
    'pirate_wallet_service_invoke_json',
    'pirate_wallet_service_free_string',
    'Java_com_pirate_wallet_sdk_NativeBridge_invokeJson',
    'Java_com_pirate_wallet_reactnative_NativeBridge_invokeJson',
  ]) {
    if (!bytes.includes(Buffer.from(`${symbol}\0`))) {
      throw new Error(`${abi} native library is missing SDK entry point ${symbol}`);
    }
  }
  if (parameterSentinels.some(sentinel => bytes.includes(sentinel))) {
    throw new Error(`${abi} native library contains embedded Sapling parameters`);
  }
  console.log(`[${expectedName}] ${abi}: ${stat.size} bytes; no embedded Sapling parameters`);
}

function main() {
  const jniLibsFlag = process.argv.indexOf('--jni-libs');
  let jniLibsDir = path.join(packageRoot, 'android/src/main/jniLibs');
  if (jniLibsFlag !== -1) {
    if (!process.argv[jniLibsFlag + 1]) {
      throw new Error('--jni-libs requires a directory');
    }
    jniLibsDir = path.resolve(process.argv[jniLibsFlag + 1]);
  } else {
    const packageJson = JSON.parse(fs.readFileSync(path.join(packageRoot, 'package.json'), 'utf8'));
    if (packageJson.name !== expectedName || packageJson.private === true) {
      throw new Error('Invalid publishable package identity');
    }
    if (!/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(packageJson.version)) {
      throw new Error('Invalid semantic version');
    }
    if (packageJson.repository?.url !== 'git+https://github.com/PirateNetwork/Stashi-Wallet.git' ||
        packageJson.publishConfig?.access !== 'public') {
      throw new Error('Repository provenance and public publishing configuration must match');
    }
    for (const relativePath of ['LICENSE-MIT', 'README.md', 'package.json']) {
      const stat = fs.statSync(path.join(packageRoot, relativePath), {throwIfNoEntry: false});
      if (!stat?.isFile() || stat.size === 0) {
        throw new Error(`Missing or empty package file: ${relativePath}`);
      }
    }
    for (const relativePath of ['ios', 'example', 'node_modules']) {
      if (fs.existsSync(path.join(packageRoot, relativePath))) {
        throw new Error(`Unexpected path: ${relativePath}`);
      }
    }
  }
  const abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
  for (const entry of fs.readdirSync(jniLibsDir)) {
    if (!abis.includes(entry)) {
      throw new Error(`Unexpected Android ABI directory: ${entry}`);
    }
  }
  for (const abi of abis) {
    const abiDirectory = path.join(jniLibsDir, abi);
    const entries = fs.readdirSync(abiDirectory);
    if (entries.length !== 1 || entries[0] !== 'libpirate_ffi_native.so') {
      throw new Error(`${abi} must contain only libpirate_ffi_native.so; found ${entries.join(', ')}`);
    }
    verifyNativeLibrary(path.join(abiDirectory, 'libpirate_ffi_native.so'), abi);
  }
}

module.exports = {verifyNativeLibrary};
if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(`[${expectedName}] ${error.message}`);
    process.exitCode = 1;
  }
}
