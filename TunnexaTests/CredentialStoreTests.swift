import XCTest
@testable import Tunnexa

final class CredentialStoreTests: XCTestCase {

    // MARK: - In-memory store

    func testInMemoryStoreRoundTrip() {
        let store = InMemoryCredentialStore()
        let id = UUID().uuidString

        XCTAssertNil(store.loadPassword(forProxyId: id), "Unknown id must return nil")
        store.savePassword("s3cret", forProxyId: id)
        XCTAssertEqual(store.loadPassword(forProxyId: id), "s3cret")
        store.savePassword("rotated", forProxyId: id)
        XCTAssertEqual(store.loadPassword(forProxyId: id), "rotated", "Overwriting must replace the value")
        store.deletePassword(forProxyId: id)
        XCTAssertNil(store.loadPassword(forProxyId: id))
    }

    func testInMemoryStoreIsolationBetweenIds() {
        let store = InMemoryCredentialStore()
        store.savePassword("one", forProxyId: "proxy-a")
        store.savePassword("two", forProxyId: "proxy-b")
        XCTAssertEqual(store.loadPassword(forProxyId: "proxy-a"), "one")
        XCTAssertEqual(store.loadPassword(forProxyId: "proxy-b"), "two")
    }

    // MARK: - Insecure fallback (obfuscation)

    func testFallbackStoreRoundTripWithUniqueSuite() {
        let suite = "group.com.rakib.tunnexa_test_\(UUID().uuidString)"
        let store = InsecureFallbackCredentialStore(suiteName: suite)
        let defaults = UserDefaults(suiteName: suite)!

        let id = UUID().uuidString
        store.savePassword("fallback-pass", forProxyId: id)

        let storedData = defaults.data(forKey: "tunnexa.proxy.password.\(id)")
        XCTAssertNotNil(storedData)
        XCTAssertNotEqual(String(data: storedData!, encoding: .utf8), "fallback-pass",
                          "Obfuscated storage must not contain the plaintext password")

        XCTAssertEqual(store.loadPassword(forProxyId: id), "fallback-pass")
        store.deletePassword(forProxyId: id)
        XCTAssertNil(store.loadPassword(forProxyId: id))
        defaults.removePersistentDomain(forName: suite)
    }

    func testFallbackStoreObfuscationDiffersFromPlaintext() {
        let suite = "group.com.rakib.tunnexa_test_\(UUID().uuidString)"
        let store = InsecureFallbackCredentialStore(suiteName: suite)
        let defaults = UserDefaults(suiteName: suite)!

        let id = UUID().uuidString
        store.savePassword("password123", forProxyId: id)
        let stored = defaults.data(forKey: "tunnexa.proxy.password.\(id)")!
        XCTAssertFalse(String(data: stored, encoding: .utf8)?.contains("password123") ?? false,
                       "Obfuscated bytes must not be recognizable")
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: - Credential store protocol conformance

    func testAllStoresConformToCredentialStoreProtocol() {
        let stores: [CredentialStore] = [
            InMemoryCredentialStore(),
            InsecureFallbackCredentialStore(suiteName: "group.com.rakib.tunnexa_test_\(UUID().uuidString)"),
        ]
        for store in stores {
            let id = UUID().uuidString
            store.savePassword("protocol-pass", forProxyId: id)
            XCTAssertEqual(store.loadPassword(forProxyId: id), "protocol-pass")
            store.deletePassword(forProxyId: id)
            XCTAssertNil(store.loadPassword(forProxyId: id))
        }
    }

    func testCredentialStorageModeDescriptions() {
        XCTAssertEqual(CredentialStorageMode.keychain.rawValue, "Keychain")
        XCTAssertEqual(CredentialStorageMode.keychainSharedGroup.rawValue, "Keychain (Shared Access Group)")
        XCTAssertEqual(CredentialStorageMode.insecureFallback.rawValue, "INSECURE Obfuscated Fallback")
        XCTAssertEqual(CredentialStorageMode.unavailable.rawValue, "Unavailable")
    }
}