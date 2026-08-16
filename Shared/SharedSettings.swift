import Foundation

// MARK: - Settings Keys & Shared Settings Store

/// Single source of truth for every UserDefaults key used by Tunnexa.
/// Never scatter raw string keys across the app.
public enum SettingsKey {
    // Behaviour
    public static let autoConnect = "setting_auto_connect"
    public static let autoReconnect = "setting_reconnect"
    public static let allowLocalNetwork = "setting_allow_local"
    public static let ipv6Enabled = "setting_ipv6"
    public static let killSwitch = "setting_kill_switch"
    public static let mtu = "setting_mtu"
    public static let appearance = "setting_appearance"

    // Local dispatcher authentication (RFC 1929 on the loopback listener)
    public static let localAuthEnabled = "setting_local_auth"
    public static let localAuthUsername = "setting_local_auth_username"
    public static let localAuthPassword = "setting_local_auth_password"

    // In-app proxy mode (LiveContainer / simulator): run the dispatcher inside
    // the app process instead of the packet tunnel.
    public static let inAppProxyEnabled = "setting_inapp_proxy"

    // Selection (wire format: by name)
    public static let selectedProxy = "selected_proxy"
    public static let selectedGroup = "selected_group"
    public static let selectedGroupOptionPrefix = "selected_group_option_"

    // Configuration
    public static let proxyConfig = "proxy_config"
    public static let configSchemaVersion = "config_schema_version"
    /// Monotonically increasing commit marker, bumped on every configuration
    /// save so the tunnel can detect a fresh snapshot without re-decoding the
    /// JSON blob. Written AFTER the config blob (commit marker semantics).
    public static let configurationGeneration = "config_generation"

    // Diagnostic session correlation (written by the tunnel, read by the app)
    public static let tunnelSessionID = "diag_tunnel_session"
    public static let engineSessionID = "diag_engine_session"

    // Statistics (written by the tunnel, read by the app)
    public static let statUploadBytes = "stat_upload_bytes"
    public static let statDownloadBytes = "stat_download_bytes"
    public static let statUploadSpeed = "stat_upload_speed"
    public static let statDownloadSpeed = "stat_download_speed"
    public static let statTunnelStart = "stat_tunnel_start"

    // Diagnostics
    public static let lastError = "last_error"
    public static let credentialStorageMode = "credential_storage_mode"
}

public enum MTULimit {
    public static let minimum = 1280
    public static let maximum = 9000
    /// Default MTU. 1500 is the de-facto Ethernet/Wi-Fi frame size and matches
    /// Apple's own default for packet tunnels; larger values (e.g. 9000 jumbo
    /// frames) can trigger fragmentation / PMTU black-holes on real networks,
    /// so they are opt-in only.
    public static let defaultValue = 1500

    public static func isValid(_ value: Int) -> Bool {
        return value >= minimum && value <= maximum
    }
}

public struct AppConfigConstants {
    public static let appGroupIdentifier = "group.com.rakib.tunnexa"
    public static let localProxyPort: UInt16 = 10808
    public static let tunnelIPv4 = "198.18.0.1"
    public static let dnsIPv4 = "198.18.0.2"
    public static let tunnelIPv6 = "fc00::1"
    public static let maxSubscriptionBytes = 5 * 1024 * 1024
    public static let maxProxyNameLength = 128
    public static let maxHostLength = 255
}

public enum CredentialStorageMode: String {
    case keychain = "Keychain"
    case keychainSharedGroup = "Keychain (Shared Access Group)"
    case insecureFallback = "INSECURE Obfuscated Fallback"
    case unavailable = "Unavailable"
}

/// Thin, validated wrapper around the shared app-group UserDefaults.
/// Falls back to `UserDefaults.standard` only for development/simulator runs
/// and logs a warning — the app and the extension MUST share the same store
/// or the tunnel cannot see the configuration.
public struct SharedSettings {
    public static let shared = SharedSettings()

    private let defaults: UserDefaults
    private static var warnedAboutFallback = false

    public init(suiteName: String = AppConfigConstants.appGroupIdentifier) {
        if let suite = UserDefaults(suiteName: suiteName) {
            self.defaults = suite
        } else {
            self.defaults = UserDefaults.standard
            if !SharedSettings.warnedAboutFallback {
                SharedSettings.warnedAboutFallback = true
                SharedLogging.log("App Group '\(suiteName)' unavailable — falling back to standard defaults. App and extension will NOT share configuration.", category: .vpn, level: .warning)
            }
        }
    }

    public var underlying: UserDefaults { defaults }

    // MARK: Accessors

    public func bool(_ key: String) -> Bool {
        return defaults.bool(forKey: key)
    }

    public func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func int(_ key: String) -> Int {
        return defaults.integer(forKey: key)
    }

    public func set(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func int64(_ key: String) -> Int64 {
        if let number = defaults.object(forKey: key) as? NSNumber {
            return number.int64Value
        }
        return 0
    }

    public func set(_ value: Int64, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func string(_ key: String) -> String? {
        return defaults.string(forKey: key)
    }

    public func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func data(_ key: String) -> Data? {
        return defaults.data(forKey: key)
    }

    public func set(_ value: Data, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }

    // MARK: Typed settings

    public var autoConnect: Bool {
        get { bool(SettingsKey.autoConnect) }
        set { set(newValue, forKey: SettingsKey.autoConnect) }
    }

    public var autoReconnect: Bool {
        get { bool(SettingsKey.autoReconnect) }
        set { set(newValue, forKey: SettingsKey.autoReconnect) }
    }

    public var allowLocalNetwork: Bool {
        get { bool(SettingsKey.allowLocalNetwork) }
        set { set(newValue, forKey: SettingsKey.allowLocalNetwork) }
    }

    public var ipv6Enabled: Bool {
        get { bool(SettingsKey.ipv6Enabled) }
        set { set(newValue, forKey: SettingsKey.ipv6Enabled) }
    }

    public var killSwitchEnabled: Bool {
        get { bool(SettingsKey.killSwitch) }
        set { set(newValue, forKey: SettingsKey.killSwitch) }
    }

    /// In-app proxy mode preference (used in LiveContainer / simulator).
    public var inAppProxyEnabled: Bool {
        get { bool(SettingsKey.inAppProxyEnabled) }
        set { set(newValue, forKey: SettingsKey.inAppProxyEnabled) }
    }

    /// Validated MTU. Invalid stored values are reported as `nil`.
    public var mtu: Int? {
        get {
            let value = int(SettingsKey.mtu)
            guard value != 0, MTULimit.isValid(value) else { return nil }
            return value
        }
        set {
            guard let value = newValue, MTULimit.isValid(value) else { return }
            set(value, forKey: SettingsKey.mtu)
        }
    }

    public var mtuOrDefault: Int {
        return mtu ?? MTULimit.defaultValue
    }

    // MARK: Configuration blob

    /// The current configuration generation, or 0 when never saved. Strictly
    /// increasing across saves; consumers treat any change as "reload now".
    public var configurationGeneration: Int64 {
        get { int64(SettingsKey.configurationGeneration) }
        set { set(newValue, forKey: SettingsKey.configurationGeneration) }
    }

    /// Generates a fresh session identifier (UUID string) for diagnostic
    /// correlation, or returns the stored one when it is still current.
    public func newSessionID(key: String) -> String {
        let id = UUID().uuidString
        set(id, forKey: key)
        return id
    }

    /// Read-only access to the last written session identifier (diagnostics
    /// must never rotate it).
    public func sessionID(key: String) -> String? {
        return string(key)
    }

    public func loadConfiguration() -> ProxyConfiguration? {
        guard let data = data(SettingsKey.proxyConfig),
              let config = try? JSONDecoder().decode(ProxyConfiguration.self, from: data) else {
            return nil
        }
        return config
    }

    @discardableResult
    public func saveConfiguration(_ config: ProxyConfiguration) -> Bool {
        do {
            let data = try JSONEncoder().encode(config)
            // Config blob first, generation second (commit marker): a reader
            // that sees the new generation is guaranteed to also see the new
            // blob, never a torn half-updated snapshot.
            set(data, forKey: SettingsKey.proxyConfig)
            configurationGeneration = configurationGeneration + 1
            return true
        } catch {
            SharedLogging.log("Failed to encode configuration: \(error.localizedDescription)", category: .vpn, level: .error)
            return false
        }
    }

    public var selectedProxyName: String {
        get { string(SettingsKey.selectedProxy) ?? "" }
        set {
            if newValue.isEmpty {
                remove(SettingsKey.selectedProxy)
            } else {
                set(newValue, forKey: SettingsKey.selectedProxy)
            }
        }
    }

    public var selectedGroupName: String {
        get { string(SettingsKey.selectedGroup) ?? "" }
        set {
            if newValue.isEmpty {
                remove(SettingsKey.selectedGroup)
            } else {
                set(newValue, forKey: SettingsKey.selectedGroup)
            }
        }
    }

    public func selectedGroupOption(for groupName: String) -> String? {
        return string(SettingsKey.selectedGroupOptionPrefix + groupName)
    }

    public func setSelectedGroupOption(_ option: String, for groupName: String) {
        set(option, forKey: SettingsKey.selectedGroupOptionPrefix + groupName)
    }

    /// True when the stored selection is usable with the given configuration.
    public static func hasValidSelection(config: ProxyConfiguration?, selectedProxy: String, selectedGroup: String) -> Bool {
        guard let config = config, config.hasUsableSelection else { return false }
        if !selectedGroup.isEmpty {
            return config.group(named: selectedGroup) != nil
        }
        if !selectedProxy.isEmpty {
            return config.proxy(named: selectedProxy) != nil
        }
        return false
    }
}