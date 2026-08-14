import Foundation

public struct SOCKS5Proxy: Codable, Identifiable, Hashable {
    public var id: UUID
    public let name: String
    public let host: String
    public let port: Int
    public let username: String?
    public let password: String?
    
    public init(id: UUID = UUID(), name: String, host: String, port: Int, username: String? = nil, password: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
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

public struct ProxyConfiguration: Codable {
    public var proxies: [SOCKS5Proxy]
    public var groups: [ProxyGroup]
    public var rules: [Rule]
    
    public init(proxies: [SOCKS5Proxy] = [], groups: [ProxyGroup] = [], rules: [Rule] = []) {
        self.proxies = proxies
        self.groups = groups
        self.rules = rules
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
}
