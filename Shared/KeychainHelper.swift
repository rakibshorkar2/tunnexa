import Foundation
import Security

// MARK: - Credential Store Protocol

/// Abstraction over credential persistence so the rest of the app can be
/// tested without touching the real Keychain.
public protocol CredentialStore: AnyObject {
    func savePassword(_ password: String, forProxyId proxyId: String)
    func loadPassword(forProxyId proxyId: String) -> String?
    func deletePassword(forProxyId proxyId: String)
}

// MARK: - Keychain Credential Store

/// Keychain-backed credential storage.
///
/// Strategy (in order of preference):
///  1. Keychain item in the process's default (per-target) keychain —
///     works with ordinary signing, including TrollStore/unsigned installs.
///  2. Keychain item with `kSecAttrAccessGroup` — used when the signing
///     profile actually authorizes `keychain-access-groups` (Apple Developer
///     signing with App Groups capability). The entitlements file does NOT
///     claim this capability by default, so this path is only exercised when
///     a provisioning profile grants it.
///  3. `InsecureFallbackCredentialStore` (shared UserDefaults obfuscation) —
///     ONLY for development / unsigned CI artifacts where neither Keychain
///     path is available. This is obfuscation, NOT encryption, and the active
///     mode is surfaced in Diagnostics and logged loudly.
public final class KeychainHelper: CredentialStore {

    public static let shared = KeychainHelper()

    private let service = "com.rakib.tunnexa"
    private let accessGroup = "group.com.rakib.tunnexa"
    private let fallback = InsecureFallbackCredentialStore.shared
    private let stateQueue = DispatchQueue(label: "com.rakib.tunnexa.keychain")

    public private(set) var activeMode: CredentialStorageMode = .unavailable
    public private(set) var lastError: OSStatus = errSecSuccess

    private init() {}

    private func accountKey(_ proxyId: String) -> String {
        return "tunnexa.proxy.password.\(proxyId)"
    }

    private func keychainQuery(proxyId: String, accessGroup: String?, valueData: Data? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(proxyId),
        ]
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        if let valueData = valueData {
            query[kSecValueData as String] = valueData
        }
        return query
    }

    // MARK: CredentialStore

    public func savePassword(_ password: String, forProxyId proxyId: String) {
        guard let passwordData = password.data(using: .utf8) else {
            SharedLogging.log("Credential save skipped: value not UTF-8 encodable.", category: .security, level: .error)
            return
        }

        // 1) Per-target keychain.
        if keychainWrite(proxyId: proxyId, accessGroup: nil, data: passwordData) {
            setMode(.keychain)
            return
        }
        // 2) Shared access group keychain (only valid when provisioned).
        if keychainWrite(proxyId: proxyId, accessGroup: accessGroup, data: passwordData) {
            setMode(.keychainSharedGroup)
            return
        }
        // 3) Insecure development fallback.
        fallback.savePassword(password, forProxyId: proxyId)
        setMode(.insecureFallback)
        warnAboutInsecureFallback()
    }

    public func loadPassword(forProxyId proxyId: String) -> String? {
        if let data = keychainRead(proxyId: proxyId, accessGroup: nil),
           let value = String(data: data, encoding: .utf8) {
            setMode(.keychain)
            return value
        }
        if let data = keychainRead(proxyId: proxyId, accessGroup: accessGroup),
           let value = String(data: data, encoding: .utf8) {
            setMode(.keychainSharedGroup)
            return value
        }
        if let value = fallback.loadPassword(forProxyId: proxyId) {
            setMode(.insecureFallback)
            return value
        }
        return nil
    }

    public func deletePassword(forProxyId proxyId: String) {
        _ = keychainDelete(proxyId: proxyId, accessGroup: nil)
        _ = keychainDelete(proxyId: proxyId, accessGroup: accessGroup)
        fallback.deletePassword(forProxyId: proxyId)
    }

    // MARK: Keychain primitives

    private func keychainWrite(proxyId: String, accessGroup: String?, data: Data) -> Bool {
        let query = keychainQuery(proxyId: proxyId, accessGroup: accessGroup)
        SecItemDelete(query as CFDictionary)
        var writeQuery = query
        writeQuery[kSecValueData as String] = data
        let status = SecItemAdd(writeQuery as CFDictionary, nil)
        if status != errSecSuccess {
            lastError = status
        }
        return status == errSecSuccess
    }

    private func keychainRead(proxyId: String, accessGroup: String?) -> Data? {
        var query = keychainQuery(proxyId: proxyId, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status != errSecSuccess {
            lastError = status
            return nil
        }
        return dataTypeRef as? Data
    }

    private func keychainDelete(proxyId: String, accessGroup: String?) -> Bool {
        let query = keychainQuery(proxyId: proxyId, accessGroup: accessGroup)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: Mode reporting

    private func setMode(_ mode: CredentialStorageMode) {
        stateQueue.sync {
            if activeMode != mode {
                activeMode = mode
                SharedSettings.shared.set(mode.rawValue, forKey: SettingsKey.credentialStorageMode)
            }
        }
    }

    private func warnAboutInsecureFallback() {
        stateQueue.sync {
            guard !didWarnAboutFallback else { return }
            didWarnAboutFallback = true
            SharedLogging.log(
                "Credential storage: Keychain unavailable (status \(lastError)). Falling back to INSECURE obfuscated storage in shared defaults. XOR obfuscation is NOT encryption — use only for development/unsigned builds.",
                category: .security,
                level: .warning
            )
        }
    }
    private var didWarnAboutFallback = false
}

// MARK: - Insecure Fallback (development / unsigned CI only)

/// UserDefaults-based obfuscation fallback.
///
/// WARNING: This is obfuscation, not encryption. It exists so development
/// builds and unsigned CI artifacts can exercise the full VPN pipeline
/// (app <-> extension credential handoff) without a provisioned Keychain.
/// The active storage mode is always surfaced in Diagnostics.
public final class InsecureFallbackCredentialStore: CredentialStore {

    public static let shared = InsecureFallbackCredentialStore()

    private let obfuscationKey: UInt8 = 0x5E
    private let defaults: UserDefaults

    public init(suiteName: String = AppConfigConstants.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
    }

    public func savePassword(_ password: String, forProxyId proxyId: String) {
        guard let data = password.data(using: .utf8) else { return }
        var obfuscated = Data(capacity: data.count)
        for byte in data {
            obfuscated.append(byte ^ obfuscationKey)
        }
        defaults.set(obfuscated, forKey: "tunnexa.proxy.password.\(proxyId)")
    }

    public func loadPassword(forProxyId proxyId: String) -> String? {
        guard let obfuscated = defaults.data(forKey: "tunnexa.proxy.password.\(proxyId)") else { return nil }
        var decoded = Data(capacity: obfuscated.count)
        for byte in obfuscated {
            decoded.append(byte ^ obfuscationKey)
        }
        return String(data: decoded, encoding: .utf8)
    }

    public func deletePassword(forProxyId proxyId: String) {
        defaults.removeObject(forKey: "tunnexa.proxy.password.\(proxyId)")
    }
}

// MARK: - In-Memory Store (tests)

public final class InMemoryCredentialStore: CredentialStore {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func savePassword(_ password: String, forProxyId proxyId: String) {
        lock.lock(); defer { lock.unlock() }
        storage[proxyId] = password
    }

    public func loadPassword(forProxyId proxyId: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[proxyId]
    }

    public func deletePassword(forProxyId proxyId: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: proxyId)
    }
}