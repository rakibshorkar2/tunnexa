import Foundation
import Security

public class KeychainHelper {
    public static let shared = KeychainHelper()
    private let service = "com.rakib.tunnexa"
    private let accessGroup = "group.com.rakib.tunnexa"
    
    // Obfuscation fallback keys
    private let obfuscationKey: UInt8 = 0x5E
    
    private init() {}
    
    private func getSharedDefaults() -> UserDefaults? {
        return UserDefaults(suiteName: accessGroup) ?? UserDefaults.standard
    }
    
    public func setPassword(_ password: String, forProxyId proxyId: String) {
        let key = "tunnexa.proxy.password.\(proxyId)"
        
        // 1. Try writing to Keychain with Access Group
        let passwordData = password.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: passwordData
        ]
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // Keychain write failed (likely due to missing signed provisioning profile for Keychain sharing in CI/dev)
            // Fallback to obfuscated storage in shared UserDefaults
            SharedLogging.log("Keychain storage failed with status \(status). Falling back to obfuscated shared UserDefaults.", category: .vpn)
            saveObfuscated(password, forKey: key)
        }
    }
    
    public func getPassword(forProxyId proxyId: String) -> String? {
        let key = "tunnexa.proxy.password.\(proxyId)"
        
        // 1. Try reading from Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data, let password = String(data: data, encoding: .utf8) {
            return password
        }
        
        // 2. Fallback: read from obfuscated shared defaults
        return readObfuscated(forKey: key)
    }
    
    public func deletePassword(forProxyId proxyId: String) {
        let key = "tunnexa.proxy.password.\(proxyId)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(query as CFDictionary)
        
        // Also clear fallback
        getSharedDefaults()?.removeObject(forKey: key)
    }
    
    // MARK: - Obfuscation Fallback
    private func saveObfuscated(_ val: String, forKey key: String) {
        guard let data = val.data(using: .utf8) else { return }
        var obfuscated = Data(capacity: data.count)
        for byte in data {
            obfuscated.append(byte ^ obfuscationKey)
        }
        getSharedDefaults()?.set(obfuscated, forKey: key)
    }
    
    private func readObfuscated(forKey key: String) -> String? {
        guard let obfuscated = getSharedDefaults()?.data(forKey: key) else { return nil }
        var decrypted = Data(capacity: obfuscated.count)
        for byte in obfuscated {
            decrypted.append(byte ^ obfuscationKey)
        }
        return String(data: decrypted, encoding: .utf8)
    }
}
