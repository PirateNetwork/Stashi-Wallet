'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {spawnSync} = require('child_process');
const {verifyNativeLibrary} = require('../../react-native-pirate-wallet-android-external/scripts/verify-package');

const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'pirate-android-packages-'));
const wrapper = path.join(temporaryRoot, 'react-native-pirate-wallet');
const resolverPath = path.join(wrapper, 'scripts/resolve-android-packages.js');
const version = '1.2.3';
const embeddedNames = ['react-native-pirate-wallet-android', 'react-native-pirate-wallet-android-x86_64'];
const externalName = 'react-native-pirate-wallet-android-external';

function makePackage(name, packageVersion = version) {
  const root = path.join(temporaryRoot, name);
  fs.mkdirSync(path.join(root, 'android/src/main/jniLibs'), {recursive: true});
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({name, version: packageVersion}));
}

function resolve(selection) {
  return spawnSync(process.execPath, [resolverPath, ...(selection ? [selection] : [])], {
    cwd: temporaryRoot,
    encoding: 'utf8',
  });
}

try {
  fs.mkdirSync(path.dirname(resolverPath), {recursive: true});
  fs.copyFileSync(path.join(__dirname, '../scripts/resolve-android-packages.js'), resolverPath);
  fs.writeFileSync(path.join(wrapper, 'package.json'), JSON.stringify({
    name: 'react-native-pirate-wallet', version,
    optionalDependencies: Object.fromEntries(embeddedNames.map(name => [name, version])),
  }));
  [...embeddedNames, externalName].forEach(name => makePackage(name));

  const defaultResult = resolve();
  assert.strictEqual(defaultResult.status, 0, defaultResult.stderr);
  const defaultPaths = JSON.parse(defaultResult.stdout);
  assert.strictEqual(defaultPaths.length, 2);
  assert(!defaultPaths.some(value => value.includes(externalName)));

  const externalResult = resolve(externalName);
  assert.strictEqual(externalResult.status, 0, externalResult.stderr);
  assert.deepStrictEqual(JSON.parse(externalResult.stdout), [
    path.join(temporaryRoot, externalName, 'android/src/main/jniLibs'),
  ]);

  // Embedded optional packages are unnecessary when external is explicitly selected.
  embeddedNames.forEach(name => fs.rmSync(path.join(temporaryRoot, name), {recursive: true}));
  assert.strictEqual(resolve(externalName).status, 0);
  assert.notStrictEqual(resolve().status, 0);
  assert.match(resolve('not-a-supported-package').stderr, /Unsupported Android binary package/);

  makePackage(externalName, '1.2.2');
  assert.match(resolve(externalName).stderr, /does not match/);
  fs.rmSync(path.join(temporaryRoot, externalName), {recursive: true});
  assert.match(resolve(externalName).stderr, /is required/);

  const fakeLibrary = path.join(temporaryRoot, 'libpirate_ffi_native.so');
  const elfHeader = Buffer.alloc(64);
  Buffer.from([0x7f, 0x45, 0x4c, 0x46, 2, 1]).copy(elfHeader);
  elfHeader.writeUInt16LE(3, 16);
  elfHeader.writeUInt16LE(183, 18);
  fs.writeFileSync(fakeLibrary, elfHeader);
  assert.throws(() => verifyNativeLibrary(fakeLibrary, 'arm64-v8a'), /missing SDK entry point/);
  fs.appendFileSync(fakeLibrary, Buffer.from([
    'pirate_wallet_service_invoke_json',
    'pirate_wallet_service_free_string',
    'Java_com_pirate_wallet_sdk_NativeBridge_invokeJson',
    'Java_com_pirate_wallet_reactnative_NativeBridge_invokeJson',
    '',
  ].join('\0')));
  verifyNativeLibrary(fakeLibrary, 'arm64-v8a');
  assert.throws(() => verifyNativeLibrary(fakeLibrary, 'x86_64'), /wrong ELF architecture/);
  fs.appendFileSync(fakeLibrary, Buffer.from(
    'c87e58906a996bb89bcb515f71408b6b79d0498511dfa90e23aec6b7cf1124f7c' +
      'cf2c50faf3ba66c136be6c30c2ff68039fafde5fc7b87ad2e9465e060b1a57e', 'hex'));
  assert.throws(() => verifyNativeLibrary(fakeLibrary, 'arm64-v8a'), /embedded Sapling parameters/);
  fs.writeFileSync(fakeLibrary, 'not an ELF library');
  assert.throws(() => verifyNativeLibrary(fakeLibrary, 'arm64-v8a'), /not ELF/);
  const descriptor = fs.openSync(fakeLibrary, 'w');
  fs.ftruncateSync(descriptor, 50_000_001);
  fs.closeSync(descriptor);
  assert.throws(() => verifyNativeLibrary(fakeLibrary, 'arm64-v8a'), /size budget/);
  console.log('Android binary selection and external parameter layout tests passed');
} finally {
  fs.rmSync(temporaryRoot, {recursive: true, force: true});
}
