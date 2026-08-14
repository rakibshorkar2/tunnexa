import Foundation

// MARK: - Core Models
//
// Tunnexa configuration model. These types are shared between the app,
// the Packet Tunnel extension and the unit tests.
//
// Identity rules:
//  - `SOCKS5Proxy.id` is a stable UUID. Display names may change; IDs never do.
//  - Rule targets and group members reference proxies/groups by NAME, because
//    that is the wire format used by imported Clash-style YAML.
//  - The stored configuration carries a `schemaVersion` (for future migrations)
//    and a monotonically increasing `revision` so the tunnel can cheaply
//    detect configuration changes without re-decoding the JSON blob.

public struct SOCKS5Proxy: Codable, Identifiable, Hashable {
    public var id: UUID
    public let name: String
    public let host: String
    public let port: Int
    public let username: String?
    /// Passwords are never persisted inside `ProxyConfiguration`.
    /// They live in the credential store, keyed by `id`.
    public let password: String?

    public init(id: UUID = UUID(), name: String, host: String, port: Int, username: String? = nil, password: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    public func sanitized() -> SOCKS5Proxy {
        return SOCKS5Proxy(id: id, name: name, host: host, port: port, username: username, password: nil)
    }
}

public enum GroupType: String, Codable, CaseIterable {
    case select = "select"
    case loadBalance = "load-balance"
}

public struct ProxyGroup: Codable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let type: GroupType
    public let proxies: [String]
    public let url: String?
    public let interval: Int?
    public let strategy: String?

    public init(name: String, type: GroupType, proxies: [String], url: String? = nil, interval: Int? = nil, strategy: String? = nil) {
        self.name = name
        self.type = type
        self.proxies = proxies
        self.url = url
        self.interval = interval
        self.strategy = strategy
    }
}

public enum RuleType: String, Codable, CaseIterable {
    case domainSuffix = "DOMAIN-SUFFIX"
    case domainKeyword = "DOMAIN-KEYWORD"
    case domain = "DOMAIN"
    case network = "NETWORK"
    case match = "MATCH"
}

public struct Rule: Codable, Hashable {
    public let type: RuleType
    public let payload: String?
    public let target: String

    public init(type: RuleType, payload: String?, target: String) {
        self.type = type
        self.payload = payload
        self.target = target
    }
}

/// Sentinel target meaning "explicitly route without a proxy".
public let RouteDirect = "DIRECT"

/// Sentinel target meaning "fail closed — block traffic".
public let RouteBlocked = "BLOCK"

public struct ProxyConfiguration: Codable {
    /// Schema version for future migrations. `nil` / `1` == current schema.
    public var schemaVersion: Int?
    /// Bumped on every committed change so consumers can detect updates cheaply.
    public var revision: Int?
    public var proxies: [SOCKS5Proxy]
    public var groups: [ProxyGroup]
    public var rules: [Rule]

    public init(proxies: [SOCKS5Proxy] = [], groups: [ProxyGroup] = [], rules: [Rule] = [], schemaVersion: Int? = 1, revision: Int? = 0) {
        self.proxies = proxies
        self.groups = groups
        self.rules = rules
        self.schemaVersion = schemaVersion
        self.revision = revision
    }

    public func proxy(named name: String) -> SOCKS5Proxy? {
        return proxies.first(where: { $0.name == name })
    }

    public func group(named name: String) -> ProxyGroup? {
        return groups.first(where: { $0.name == name })
    }

    /// Whether the stored configuration actually contains usable routes.
    public var hasUsableSelection: Bool {
        return !proxies.isEmpty || !groups.isEmpty
    }

    /// Deterministically validates that every rule target / group member that
    /// is neither DIRECT nor BLOCK refers to an existing proxy or group.
    public var unresolvedReferences: [String] {
        var unresolved = Set<String>()
        for g in groups {
            for member in g.proxies where member != RouteDirect && member != RouteBlocked {
                if proxy(named: member) == nil && group(named: member) == nil {
                    unresolved.insert(member)
                }
            }
        }
        for rule in rules where rule.target != RouteDirect && rule.target != RouteBlocked {
            if proxy(named: rule.target) == nil && group(named: rule.target) == nil {
                unresolved.insert(rule.target)
            }
        }
        return unresolved.sorted()
    }
}

public enum ProxyStatus: String, Codable {
    case unknown = "Unknown"
    case checking = "Checking..."
    case online = "Online"
    case slow = "Slow"
    case authFailed = "Authentication Failed"
    case connFailed = "Connection Failed"
    case timeout = "Timeout"
    case protocolError = "Protocol Error"
}
