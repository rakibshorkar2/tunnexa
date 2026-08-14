import Foundation

public enum YAMLParsingError: Error, LocalizedError {
    case invalidStructure
    case missingProxiesSection
    case invalidPort(String)
    case missingRequiredField(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidStructure:
            return "The YAML file has an invalid structure."
        case .missingProxiesSection:
            return "The 'proxies' section is missing or empty."
        case .invalidPort(let portStr):
            return "Invalid port value: '\(portStr)'. Port must be in range 1-65535."
        case .missingRequiredField(let field):
            return "Required field '\(field)' is missing from a proxy definition."
        }
    }
}

public class YAMLParser {
    
    public static func parse(_ content: String) throws -> ProxyConfiguration {
        var proxies: [SOCKS5Proxy] = []
        var groups: [ProxyGroup] = []
        var rules: [Rule] = []
        
        let lines = content.components(separatedBy: .newlines)
        var currentSection = ""
        var currentItem: [String: Any] = [:]
        var currentListKey: String? = nil
        var currentListItems: [String] = []
        
        func flushItem() {
            if currentItem.isEmpty { return }
            if currentSection == "proxies" {
                if let name = currentItem["name"] as? String,
                   let type = currentItem["type"] as? String, type == "socks5",
                   let server = currentItem["server"] as? String,
                   let port = currentItem["port"] as? Int {
                    let username = currentItem["username"] as? String
                    let password = currentItem["password"] as? String
                    proxies.append(SOCKS5Proxy(id: UUID(), name: name, host: server, port: port, username: username, password: password))
                }
            } else if currentSection == "proxy-groups" {
                if let name = currentItem["name"] as? String,
                   let typeStr = currentItem["type"] as? String,
                   let type = GroupType(rawValue: typeStr) {
                    let url = currentItem["url"] as? String
                    let interval = currentItem["interval"] as? Int
                    let strategy = currentItem["strategy"] as? String
                    groups.append(ProxyGroup(name: name, type: type, proxies: currentListItems, url: url, interval: interval, strategy: strategy))
                }
            }
            currentItem = [:]
            currentListItems = []
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            // Section check
            if line.hasPrefix("proxies:") {
                flushItem()
                currentSection = "proxies"
                currentListKey = nil
                continue
            } else if line.hasPrefix("proxy-groups:") {
                flushItem()
                currentSection = "proxy-groups"
                currentListKey = nil
                continue
            } else if line.hasPrefix("rules:") {
                flushItem()
                currentSection = "rules"
                currentListKey = nil
                continue
            }
            
            // If in rules section, rules are simple lists
            if currentSection == "rules" {
                if trimmed.hasPrefix("-") {
                    var ruleStr = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                    // Remove quotes if present
                    if (ruleStr.hasPrefix("'") && ruleStr.hasSuffix("'")) || (ruleStr.hasPrefix("\"") && ruleStr.hasSuffix("\"")) {
                        ruleStr = String(ruleStr.dropFirst().dropLast())
                    }
                    let parts = ruleStr.components(separatedBy: ",")
                    if parts.count == 3 {
                        let typeRaw = parts[0].trimmingCharacters(in: .whitespaces)
                        let payload = parts[1].trimmingCharacters(in: .whitespaces)
                        let target = parts[2].trimmingCharacters(in: .whitespaces)
                        if let type = RuleType(rawValue: typeRaw) {
                            rules.append(Rule(type: type, payload: payload, target: target))
                        }
                    } else if parts.count == 2 {
                        let typeRaw = parts[0].trimmingCharacters(in: .whitespaces)
                        let target = parts[1].trimmingCharacters(in: .whitespaces)
                        if let type = RuleType(rawValue: typeRaw), type == .match {
                            rules.append(Rule(type: type, payload: nil, target: target))
                        }
                    }
                }
                continue
            }
            
            // Parsing proxy list and group list
            if trimmed.hasPrefix("-") {
                flushItem()
                // New item starts
                let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty {
                    if currentSection == "proxy-groups" && currentListKey != nil {
                        var val = rest
                        if (val.hasPrefix("'") && val.hasSuffix("'")) || (val.hasPrefix("\"") && val.hasSuffix("\"")) {
                            val = String(val.dropFirst().dropLast())
                        }
                        currentListItems.append(val)
                    } else {
                        parseKeyValue(rest, into: &currentItem)
                    }
                }
            } else {
                if trimmed.contains(":") {
                    let parts = trimmed.split(separator: ":", maxSplits: 1)
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    var val = parts[1].trimmingCharacters(in: .whitespaces)
                    
                    if val.isEmpty {
                        currentListKey = key
                        currentListItems = []
                    } else {
                        if (val.hasPrefix("'") && val.hasSuffix("'")) || (val.hasPrefix("\"") && val.hasSuffix("\"")) {
                            val = String(val.dropFirst().dropLast())
                        }
                        
                        if key == "port" || key == "interval" {
                            currentItem[key] = Int(val) ?? 0
                        } else {
                            currentItem[key] = val
                        }
                    }
                } else if currentListKey != nil {
                    var val = trimmed
                    if val.hasPrefix("-") {
                        val = val.dropFirst().trimmingCharacters(in: .whitespaces)
                    }
                    if (val.hasPrefix("'") && val.hasSuffix("'")) || (val.hasPrefix("\"") && val.hasSuffix("\"")) {
                        val = String(val.dropFirst().dropLast())
                    }
                    if !val.isEmpty {
                        currentListItems.append(val)
                    }
                }
            }
        }
        
        flushItem()
        
        guard !proxies.isEmpty else {
            throw YAMLParsingError.missingProxiesSection
        }
        
        // Basic validation
        for proxy in proxies {
            if proxy.host.isEmpty {
                throw YAMLParsingError.missingRequiredField("server")
            }
            if proxy.port < 1 || proxy.port > 65535 {
                throw YAMLParsingError.invalidPort(String(proxy.port))
            }
            if proxy.name.isEmpty {
                throw YAMLParsingError.missingRequiredField("name")
            }
        }
        
        return ProxyConfiguration(proxies: proxies, groups: groups, rules: rules)
    }
    
    private static func parseKeyValue(_ line: String, into dict: inout [String: Any]) {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        var val = parts[1].trimmingCharacters(in: .whitespaces)
        if (val.hasPrefix("'") && val.hasSuffix("'")) || (val.hasPrefix("\"") && val.hasSuffix("\"")) {
            val = String(val.dropFirst().dropLast())
        }
        if key == "port" || key == "interval" {
            dict[key] = Int(val) ?? 0
        } else {
            dict[key] = val
        }
    }
}
