import Cocoa
import FlutterMacOS
import XCTest
import Security
@testable import Stashi_Wallet

class RunnerTests: XCTestCase {

  func testPreferenceMigrationRunsOnceAndKeepsNewSelections() {
    let suite = "StashiPreferenceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var reads = 0
    let store = MacPreferenceStorage(defaults: defaults) { _ in
      reads += 1
      return "light"
    }
    XCTAssertEqual(store.read(key: "ui_theme_mode_v1"), "light")
    store.write(key: "ui_theme_mode_v1", value: "dark")
    XCTAssertEqual(store.read(key: "ui_theme_mode_v1"), "dark")
    XCTAssertEqual(reads, 1)
  }

  func testDeniedLegacyAccessDoesNotEnableRequestsOrReadSecrets() {
    let suite = "StashiPreferenceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var reads = 0
    let store = MacPreferenceStorage(defaults: defaults) { _ in
      reads += 1
      return nil
    }
    XCTAssertEqual(store.read(key: "ui_external_api_master_v1"), "false")
    XCTAssertEqual(store.read(key: "ui_external_api_master_v1"), "false")
    XCTAssertEqual(reads, 1)
    for key in ["pirate_wallet_master_key", "app_passphrase_wrapped_v1", "transport_config_v1"] {
      XCTAssertNil(store.read(key: key))
      store.write(key: key, value: "must-not-persist")
      XCTAssertNil(defaults.string(forKey: "stashi.preferences.\(key)"))
    }
    XCTAssertEqual(reads, 1)
  }

  func testLegacyPreferenceLookupCannotDisplayAuthorizationUI() {
    let query = MacPreferenceStorage.legacyQuery(key: "ui_theme_mode_v1")
    XCTAssertEqual(query[kSecUseAuthenticationUI as String] as? String,
                   kSecUseAuthenticationUIFail as String)
    XCTAssertEqual(query[kSecAttrService as String] as? String,
                   "flutter_secure_storage_service")
  }

}
