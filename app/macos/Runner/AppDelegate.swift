import Cocoa
import FlutterMacOS
import Security
import LocalAuthentication

final class MacPreferenceStorage {
  private let defaults: UserDefaults
  private let legacyRead: (String) -> String?

  init(defaults: UserDefaults = .standard,
       legacyRead: ((String) -> String?)? = nil) {
    self.defaults = defaults
    self.legacyRead = legacyRead ?? Self.readLegacy
  }

  func read(key: String) -> String? {
    guard Self.allowedKeys.contains(key) else { return nil }
    let defaultsKey = "stashi.preferences.\(key)"
    if let value = defaults.string(forKey: defaultsKey) { return value }
    // Inaccessible consent must not enable external requests or unlock.
    let fallback = key.hasPrefix("ui_external_api_") || key == "ui_biometrics_enabled_v1"
      ? "false" : ""
    let value = legacyRead(key) ?? fallback
    defaults.set(value, forKey: defaultsKey)
    return value
  }

  func write(key: String, value: String) {
    guard Self.allowedKeys.contains(key) else { return }
    defaults.set(value, forKey: "stashi.preferences.\(key)")
  }

  static func legacyQuery(key: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "flutter_secure_storage_service",
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
    ]
  }

  private static func readLegacy(key: String) -> String? {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(legacyQuery(key: key) as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
  // This allowlist is a security boundary: no key material, passphrases, wallet
  // history, endpoint credentials or arbitrary Keychain items belong here.
  static let allowedKeys: Set<String> = [
    "ui_theme_mode_v1", "ui_theme_style_v1", "ui_currency_pref_v1",
    "ui_swap_interface_pref_v1", "ui_locale_pref_v1", "seed_phrase_language_pref_v1",
    "ui_biometrics_enabled_v1", "ui_balance_primary_fiat_v1",
    "ui_external_api_master_v1", "ui_external_api_prices_v1",
    "ui_external_api_github_v1", "ui_external_api_desktop_updates_v1",
    "ui_external_api_komodo_swaps_v1", "ui_debug_logging_enabled_v1",
    "sync_last_known_height_v1", "ui_update_prompt_dismissed_tag_v1"
  ]

}

@main
class AppDelegate: FlutterAppDelegate {
  private let keystoreService = "com.pirate.wallet.keystore"
  private let masterKeyAccount = "pirate_wallet_master_key"
  private let sealedKeyMarker = Data("macos-keychain-v1".utf8)
  private var securityChannel: FlutterMethodChannel?

  private let preferences = MacPreferenceStorage()

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.pirate.wallet/keystore",
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        self.handleKeystoreCall(call: call, result: result)
      }

      let security = FlutterMethodChannel(
        name: "com.pirate.wallet/security",
        binaryMessenger: controller.engine.binaryMessenger
      )
      securityChannel = security
      security.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "enableScreenshotProtection":
          DispatchQueue.main.async {
            self.mainFlutterWindow?.sharingType = .none
            result(true)
          }
        case "disableScreenshotProtection":
          DispatchQueue.main.async {
            self.mainFlutterWindow?.sharingType = .readOnly
            result(true)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func handleKeystoreCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "readPreference", "writePreference":
      guard let args = call.arguments as? [String: Any],
            let key = args["key"] as? String, MacPreferenceStorage.allowedKeys.contains(key) else {
        result(FlutterError(code: "INVALID_PREFERENCE", message: "Unsupported preference", details: nil))
        return
      }
      if call.method == "writePreference" {
        guard let value = args["value"] as? String else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Preference value required", details: nil))
          return
        }
        preferences.write(key: key, value: value)
        result(nil)
      } else {
        result(preferences.read(key: key))
      }
    case "storeKey":
      guard let args = call.arguments as? [String: Any],
            let keyId = args["keyId"] as? String,
            let encryptedKey = args["encryptedKey"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "keyId and encryptedKey required", details: nil))
        return
      }
      do {
        try storeKeychainData(encryptedKey.data, account: keyId)
        result(true)
      } catch {
        result(FlutterError(code: "KEYSTORE_ERROR", message: formatKeystoreError(error), details: nil))
      }
    case "retrieveKey":
      guard let args = call.arguments as? [String: Any],
            let keyId = args["keyId"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "keyId required", details: nil))
        return
      }
      do {
        if let data = try loadKeychainData(account: keyId) {
          result(FlutterStandardTypedData(bytes: data))
        } else {
          result(nil)
        }
      } catch {
        result(FlutterError(code: "KEYSTORE_ERROR", message: formatKeystoreError(error), details: nil))
      }
    case "deleteKey":
      guard let args = call.arguments as? [String: Any],
            let keyId = args["keyId"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "keyId required", details: nil))
        return
      }
      do {
        try deleteKeychainData(account: keyId)
        result(true)
      } catch {
        result(FlutterError(code: "KEYSTORE_ERROR", message: formatKeystoreError(error), details: nil))
      }
    case "keyExists":
      guard let args = call.arguments as? [String: Any],
            let keyId = args["keyId"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "keyId required", details: nil))
        return
      }
      result(keyExists(account: keyId))
    case "sealMasterKey":
      guard let args = call.arguments as? [String: Any],
            let masterKey = args["masterKey"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "masterKey required", details: nil))
        return
      }
      do {
        // Store wrapped passphrase secret in Keychain. Biometric enforcement
        // is handled by local_auth in the unlock flow for desktop builds.
        try storeKeychainData(
          masterKey.data,
          account: masterKeyAccount,
          requireBiometric: true
        )
        // Return a non-empty marker so Dart-side cache existence checks work.
        result(FlutterStandardTypedData(bytes: sealedKeyMarker))
      } catch {
        result(FlutterError(code: "SEAL_ERROR", message: formatKeystoreError(error), details: nil))
      }
    case "unsealMasterKey":
      guard let args = call.arguments as? [String: Any],
            let _ = args["sealedKey"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "sealedKey required", details: nil))
        return
      }
      do {
        if let data = try loadKeychainData(
          account: masterKeyAccount,
          requireBiometric: true
        ) {
          result(FlutterStandardTypedData(bytes: data))
        } else {
          result(FlutterError(code: "UNSEAL_ERROR", message: "Master key not found", details: nil))
        }
      } catch {
        result(FlutterError(code: "UNSEAL_ERROR", message: formatKeystoreError(error), details: nil))
      }
    case "getCapabilities":
      result(getCapabilities())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func storeKeychainData(
    _ data: Data,
    account: String,
    requireBiometric _: Bool = false
  ) throws {
    let baseQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keystoreService,
      kSecAttrAccount as String: account
    ]

    var addQuery = baseQuery
    addQuery[kSecValueData as String] = data

    // Keep macOS keychain mode stable across signed/unsigned desktop builds.
    // Biometric gating is enforced at unlock time via local_auth.
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    // Preserve the existing item's access grants. Delete-then-add discards
    // Always Allow decisions and can lose the old secret if insertion fails.
    let updateStatus = SecItemUpdate(baseQuery as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
    if updateStatus == errSecSuccess { return }
    if updateStatus != errSecItemNotFound {
      throw NSError(domain: "KeystoreError", code: Int(updateStatus), userInfo: nil)
    }

    let status = SecItemAdd(addQuery as CFDictionary, nil)
    if status != errSecSuccess {
      throw NSError(domain: "KeystoreError", code: Int(status), userInfo: nil)
    }
  }

  private func loadKeychainData(
    account: String,
    requireBiometric _: Bool = false
  ) throws -> Data? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keystoreService,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return nil
    }
    if status != errSecSuccess {
      throw NSError(domain: "KeystoreError", code: Int(status), userInfo: nil)
    }
    return (item as? Data)
  }

  private func deleteKeychainData(account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keystoreService,
      kSecAttrAccount as String: account
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      throw NSError(domain: "KeystoreError", code: Int(status), userInfo: nil)
    }
  }

  private func keyExists(account: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keystoreService,
      kSecAttrAccount as String: account,
      kSecReturnData as String: false,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess
  }

  private func getCapabilities() -> [String: Bool] {
    let context = LAContext()
    var error: NSError?
    let hasBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    let hasSecureEnclave = secureEnclaveAvailable()
    return [
      "hasSecureHardware": hasSecureEnclave,
      "hasStrongBox": false,
      "hasSecureEnclave": hasSecureEnclave,
      "hasBiometrics": hasBiometrics
    ]
  }

  private func secureEnclaveAvailable() -> Bool {
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecAttrIsPermanent as String: false
    ]
    var error: Unmanaged<CFError>?
    return SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil
  }

  private func formatKeystoreError(_ error: Error) -> String {
    let nsError = error as NSError
    if nsError.domain == NSOSStatusErrorDomain || nsError.domain == "KeystoreError" {
      return "\(nsError.localizedDescription) (OSStatus: \(nsError.code))"
    }
    return nsError.localizedDescription
  }
}
