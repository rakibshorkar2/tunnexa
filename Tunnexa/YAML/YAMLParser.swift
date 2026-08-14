import Foundation

// MARK: - Errors

/// A single semantic validation problem with a precise location.
public struct YAMLValidationIssue: Error, Equatable {
    public let line: Int
    public let field: String
    public let reason: String

    public init(line: Int, field: String, reason: String) {
        self.line = line
        self.field = field
        self.reason = reason
    }

    public var description: String {
        return "Line \(line): \(reason)"
    }
}

public enum YAMLParsingError: Error, LocalizedError, Equatable {
    /// The document has no usable `proxies` section.
    case missingProxiesSection
    /// Structural problem (tabs, bad indentation, unclosed quote, ...).
    case invalidStructure(line: Int, message: String)
    /// One or more semantic validation problems.
    case validation([YAMLValidationIssue])

    public var errorDescription: String? {
        switch self {
        case .missingProxiesSection:
            return "The 'proxies' section is missing or empty."
        case .invalidStructure(let line, let message):
            return "Line \(line): \(message)"
        case .validation(let issues):
            return issues.map { $0.description }.joined(separator: "\n")
        }
    }
}

// MARK: - Import summary

/// Everything the importer learned from a YAML document, including skipped
/// content (unsupported proxy types / rule types) so the UI can report it.
public struct YAMLImportSummary {
    public let proxiesCount: Int
    public let groupsCount: Int
    public let rulesCount: Int
    public let skippedProxies: Int
    public let skippedRules: Int
    public let warnings: [String]
    public let configuration: ProxyConfiguration
}

// MARK: - YAML value tree

fileprivate enum YAMLValue {
    case scalar(String, line: Int)
    case mapping([String: YAMLNode], line: Int)
    case sequence([YAMLNode], line: Int)
}

fileprivate struct YAMLNode {
    let value: YAMLValue

    var line: Int {
        switch value {
        case .scalar(_, let line), .mapping(_, let line), .sequence(_, let line):
            return line
        }
    }

    var scalar: String? {
        if case .scalar(let s, _) = value { return s }
        return nil
    }

    var mapping: [String: YAMLNode]? {
        if case .mapping(let m, _) = value { return m }
        return nil
    }

    var sequence: [YAMLNode]? {
        if case .sequence(let s, _) = value { return s }
        return nil
    }
}

// MARK: - Parser

/// A small, indentation-aware YAML subset parser.
///
/// Supported:
///  - block mappings and sequences (2-space indentation convention, any
///    consistent indentation is accepted);
///  - single- and double-quoted scalars with basic escaping;
///  - inline comments (` # comment`) and full-line comments;
///  - CRLF / LF / CR line endings;
///  - inline flow lists `[a, b]`.
///
/// Rejected with precise line numbers: tabs in indentation, inconsistent
/// indentation, unclosed quotes, empty list items.
public class YAMLParser {

    // MARK: Public API

    public static func parse(_ content: String) throws -> ProxyConfiguration {
        return try parseDetailed(content).configuration
    }

    public static func parseDetailed(_ content: String) throws -> YAMLImportSummary {
        let lines = try tokenize(content)
        guard !lines.isEmpty else {
            throw YAMLParsingError.missingProxiesSection
        }
        let root = try parseBlock(lines, at: 0, indent: lines[0].indent)
        return try validate(root)
    }

    // MARK: Tokenization

    fileprivate struct Line {
        let number: Int
        let indent: Int
        let content: String
    }

    private static func tokenize(_ content: String) throws -> [Line] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var result: [Line] = []
        for (index, rawLine) in normalized.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let raw = String(rawLine)

            // Tabs are never legal YAML indentation.
            if raw.hasPrefix("\t") {
                throw YAMLParsingError.invalidStructure(line: lineNumber, message: "Tab characters are not allowed for indentation.")
            }
            let indent = raw.prefix(while: { $0 == " " }).count
            let content = String(raw.dropFirst(indent)).trimmingCharacters(in: .whitespaces)

            // Skip blank lines, comments and document markers.
            if content.isEmpty || content.hasPrefix("#") || content == "---" || content == "..." {
                continue
            }
            result.append(Line(number: lineNumber, indent: indent, content: content))
        }
        return result
    }

    // MARK: Block parsing

    private static func parseBlock(_ lines: [Line], at start: Int, indent: Int) throws -> (YAMLValue, Int) {
        guard start < lines.count else {
            return (.mapping([:], line: lines.last?.number ?? 0), start)
        }
        let content = lines[start].content
        if content.hasPrefix("- ") || content == "-" {
            return try parseSequence(lines, at: start, indent: indent)
        }
        return try parseMapping(lines, at: start, indent: indent)
    }

    /// Splits `key: value`, honouring quotes. Returns nil when the line is not
    /// a key/value pair (e.g. a bare scalar or a quoted string containing a colon).
    private static func splitKeyValue(_ text: String) -> (key: String, value: String)? {
        var quote: Character? = nil
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if let q = quote {
                if char == q {
                    quote = nil
                }
            } else if char == "\"" || char == "'" {
                quote = char
            } else if char == ":" {
                let key = text[text.startIndex..<index]
                let value = text[text.index(after: index)...]
                let trimmedKey = String(key).trimmingCharacters(in: .whitespaces)
                let trimmedValue = String(value).trimmingCharacters(in: .whitespaces)
                guard !trimmedKey.isEmpty else { return nil }
                return (trimmedKey, trimmedValue)
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func parseMapping(_ lines: [Line], at start: Int, indent: Int) throws -> (YAMLValue, Int) {
        var mapping: [String: YAMLNode] = [:]
        var i = start
        while i < lines.count {
            let line = lines[i]
            if line.indent < indent { break }
            if line.indent > indent {
                throw YAMLParsingError.invalidStructure(line: line.number, message: "Unexpected indentation (expected level \(indent)).")
            }
            guard let split = splitKeyValue(line.content) else {
                throw YAMLParsingError.invalidStructure(line: line.number, message: "Expected 'key: value' but found '\(line.content)'.")
            }
            let key = unquoteKey(split.key)
            guard !key.isEmpty else {
                throw YAMLParsingError.invalidStructure(line: line.number, message: "Empty mapping key.")
            }
            i += 1

            if split.value.isEmpty {
                // Nested block or empty value.
                if i < lines.count, lines[i].indent > indent {
                    let (nested, next) = try parseBlock(lines, at: i, indent: lines[i].indent)
                    mapping[key] = YAMLNode(value: nested)
                    i = next
                } else {
                    mapping[key] = YAMLNode(value: .scalar("", line: line.number))
                }
            } else {
                mapping[key] = YAMLNode(value: .scalar(parseScalar(split.value, lineNumber: line.number), line: line.number))
                // A value was provided inline; any deeper content is an error.
                if i < lines.count, lines[i].indent > indent {
                    throw YAMLParsingError.invalidStructure(line: lines[i].number, message: "Unexpected indentation below scalar value for key '\(key)'.")
                }
            }
        }
        return (.mapping(mapping, line: lines[start].number), i)
    }

    private static func parseSequence(_ lines: [Line], at start: Int, indent: Int) throws -> (YAMLValue, Int) {
        var items: [YAMLNode] = []
        var i = start
        while i < lines.count {
            let line = lines[i]
            if line.indent < indent { break }
            if line.indent > indent {
                throw YAMLParsingError.invalidStructure(line: line.number, message: "Unexpected indentation (expected level \(indent)).")
            }
            guard line.content.hasPrefix("-") else {
                throw YAMLParsingError.invalidStructure(line: line.number, message: "Expected list item starting with '-' but found '\(line.content)'.")
            }
            let rest = String(line.content.dropFirst()).trimmingCharacters(in: .whitespaces)
            i += 1

            if rest.isEmpty {
                guard i < lines.count, lines[i].indent > indent else {
                    throw YAMLParsingError.invalidStructure(line: line.number, message: "Empty list item (no value or nested block below '-').")
                }
                let (nested, next) = try parseBlock(lines, at: i, indent: lines[i].indent)
                items.append(YAMLNode(value: nested))
                i = next
                continue
            }

            if let split = splitKeyValue(rest) {
                // Mapping-style list item: `- key: value`, with continuation
                // keys at any deeper indentation.
                let itemLine = line.number
                var item: [String: YAMLNode] = [:]
                var firstValue = parseScalar(split.value, lineNumber: itemLine)
                var firstKey = unquoteKey(split.key)

                if split.value.isEmpty {
                    if i < lines.count, lines[i].indent > indent {
                        let (nested, next) = try parseBlock(lines, at: i, indent: lines[i].indent)
                        item[firstKey] = YAMLNode(value: nested)
                        i = next
                    } else {
                        item[firstKey] = YAMLNode(value: .scalar("", line: itemLine))
                    }
                } else {
                    item[firstKey] = YAMLNode(value: .scalar(firstValue, line: itemLine))
                }

                // Continuation keys.
                while i < lines.count {
                    let nextLine = lines[i]
                    if nextLine.indent <= indent { break }
                    guard let nextSplit = splitKeyValue(nextLine.content) else {
                        throw YAMLParsingError.invalidStructure(line: nextLine.number, message: "Expected 'key: value' continuation for list item but found '\(nextLine.content)'.")
                    }
                    let key = unquoteKey(nextSplit.key)
                    i += 1
                    if nextSplit.value.isEmpty {
                        if i < lines.count, lines[i].indent > nextLine.indent {
                            let (nested, next) = try parseBlock(lines, at: i, indent: lines[i].indent)
                            item[key] = YAMLNode(value: nested)
                            i = next
                        } else {
                            item[key] = YAMLNode(value: .scalar("", line: nextLine.number))
                        }
                    } else {
                        item[key] = YAMLNode(value: .scalar(parseScalar(nextSplit.value, lineNumber: nextLine.number), line: nextLine.number))
                        if i < lines.count, lines[i].indent > nextLine.indent {
                            throw YAMLParsingError.invalidStructure(line: lines[i].number, message: "Unexpected indentation below scalar value for key '\(key)'.")
                        }
                    }
                }
                items.append(YAMLNode(value: .mapping(item, line: itemLine)))
            } else {
                // Scalar list item (rules, group members, ...).
                items.append(YAMLNode(value: .scalar(parseScalar(rest, lineNumber: line.number), line: line.number)))
            }
        }
        return (.sequence(items, line: lines[start].number), i)
    }

    // MARK: Scalar handling

    private static func unquoteKey(_ key: String) -> String {
        return parseScalar(key, lineNumber: 0)
    }

    private static func parseScalar(_ raw: String, lineNumber: Int) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)

        if text.hasPrefix("\"") {
            guard text.count >= 2, text.hasSuffix("\"") else {
                return text
            }
            text = String(text.dropFirst().dropLast())
            text = text
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
            return text
        }
        if text.hasPrefix("'") {
            guard text.count >= 2, text.hasSuffix("'") else {
                return text
            }
            text = String(text.dropFirst().dropLast())
            return text.replacingOccurrences(of: "''", with: "'")
        }
        // Unquoted: inline comments start at " #".
        if let range = text.range(of: " #") {
            text = String(text[text.startIndex..<range.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Validation

    private static func validate(_ root: YAMLValue) throws -> YAMLImportSummary {
        guard case .mapping(let top, _) = root else {
            throw YAMLParsingError.invalidStructure(line: 1, message: "The document must be a mapping.")
        }

        var issues: [YAMLValidationIssue] = []
        var warnings: [String] = []
        var skippedProxies = 0
        var skippedRules = 0

        let proxiesNode = top["proxies"]
        let groupsNode = top["proxy-groups"]
        let rulesNode = top["rules"]

        // proxies is required and must be non-empty.
        guard let proxyItems = proxiesNode?.sequence, !proxyItems.isEmpty else {
            throw YAMLParsingError.missingProxiesSection
        }

        // ---- proxies ----
        var proxies: [SOCKS5Proxy] = []
        var proxyNames = Set<String>()
        for node in proxyItems {
            guard let mapping = node.mapping else {
                issues.append(YAMLValidationIssue(line: node.line, field: "proxies", reason: "Proxy entry must be a mapping (name/type/server/port)."))
                continue
            }
            let name = mapping["name"]?.scalar ?? ""
            let type = (mapping["type"]?.scalar ?? "").lowercased()
            let server = mapping["server"]?.scalar ?? ""
            let portValue = mapping["port"]?.scalar ?? ""
            let username = mapping["username"]?.scalar
            let password = mapping["password"]?.scalar

            if name.isEmpty {
                issues.append(YAMLValidationIssue(line: node.line, field: "name", reason: "Proxy is missing a 'name'."))
            }
            if proxyNames.contains(name) {
                issues.append(YAMLValidationIssue(line: node.line, field: "name", reason: "Duplicate proxy name '\(name)'."))
            }
            proxyNames.insert(name)

            if type != "socks5" {
                let skippedType = type.isEmpty ? "<missing>" : type
                warnings.append("Line \(node.line): proxy '\(name)' has unsupported type '\(skippedType)' and was skipped.")
                skippedProxies += 1
                continue
            }
            if server.isEmpty {
                issues.append(YAMLValidationIssue(line: node.line, field: "server", reason: "Proxy '\(name)' is missing a 'server'."))
            }
            guard let port = Int(portValue), (1...65535).contains(port) else {
                issues.append(YAMLValidationIssue(line: node.line, field: "port", reason: "Proxy '\(name)' has invalid port '\(portValue)' (must be 1-65535)."))
                continue
            }
            proxies.append(SOCKS5Proxy(id: UUID(), name: name, host: server, port: port, username: username, password: password))
        }

        // ---- proxy-groups ----
        var groups: [ProxyGroup] = []
        var groupNames = Set<String>()
        if let groupItems = groupsNode?.sequence {
            for node in groupItems {
                guard let mapping = node.mapping else {
                    issues.append(YAMLValidationIssue(line: node.line, field: "proxy-groups", reason: "Group entry must be a mapping (name/type/proxies)."))
                    continue
                }
                let name = mapping["name"]?.scalar ?? ""
                let typeRaw = mapping["type"]?.scalar ?? ""
                let type = GroupType(rawValue: typeRaw)
                let members = mapping["proxies"]?.sequence ?? []

                if name.isEmpty {
                    issues.append(YAMLValidationIssue(line: node.line, field: "name", reason: "Group is missing a 'name'."))
                }
                if groupNames.contains(name) {
                    issues.append(YAMLValidationIssue(line: node.line, field: "name", reason: "Duplicate group name '\(name)'."))
                }
                groupNames.insert(name)

                guard let resolvedType = type else {
                    issues.append(YAMLValidationIssue(line: node.line, field: "type", reason: "Group '\(name)' has unsupported type '\(typeRaw)' (supported: select, load-balance)."))
                    continue
                }
                var memberNames: [String] = []
                for member in members {
                    if let scalar = member.scalar, !scalar.isEmpty {
                        memberNames.append(scalar)
                    }
                }
                if memberNames.isEmpty {
                    issues.append(YAMLValidationIssue(line: node.line, field: "proxies", reason: "Group '\(name)' has no members."))
                }

                let url = mapping["url"]?.scalar
                let interval = mapping["interval"]?.scalar.flatMap { Int($0) }
                let strategy = mapping["strategy"]?.scalar
                groups.append(ProxyGroup(name: name, type: resolvedType, proxies: memberNames, url: url, interval: interval, strategy: strategy))
            }
        }

        // ---- rules ----
        var rules: [Rule] = []
        if let ruleItems = rulesNode?.sequence {
            for node in ruleItems {
                guard let scalar = node.scalar else {
                    issues.append(YAMLValidationIssue(line: node.line, field: "rules", reason: "Rule must be a quoted or unquoted string."))
                    continue
                }
                let parts = scalar.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                guard !parts.isEmpty, !parts[0].isEmpty else {
                    issues.append(YAMLValidationIssue(line: node.line, field: "rules", reason: "Malformed rule '\(scalar)'."))
                    continue
                }
                guard let type = RuleType(rawValue: parts[0]) else {
                    warnings.append("Line \(node.line): unsupported rule type '\(parts[0])' was skipped.")
                    skippedRules += 1
                    continue
                }
                switch type {
                case .match:
                    guard parts.count == 2, !parts[1].isEmpty else {
                        issues.append(YAMLValidationIssue(line: node.line, field: "rules", reason: "MATCH rule must have exactly one target (e.g. 'MATCH,DIRECT')."))
                        continue
                    }
                    rules.append(Rule(type: .match, payload: nil, target: parts[1]))
                case .domain, .domainSuffix, .domainKeyword:
                    guard parts.count == 3, !parts[1].isEmpty else {
                        issues.append(YAMLValidationIssue(line: node.line, field: "rules", reason: "\(parts[0]) rule must have a payload and a target (e.g. '\(parts[0]),example.com,PROXY')."))
                        continue
                    }
                    rules.append(Rule(type: type, payload: parts[1], target: parts[2]))
                case .network:
                    guard parts.count == 3, !parts[1].isEmpty, isNetworkPayloadValid(parts[1]) else {
                        issues.append(YAMLValidationIssue(line: node.line, field: "rules", reason: "NETWORK rule payload must be TCP, UDP, TCP,UDP, an IP address or a CIDR block."))
                        continue
                    }
                    rules.append(Rule(type: .network, payload: parts[1], target: parts[2]))
                }
            }
        }

        // ---- reference resolution ----
        for group in groups {
            for member in group.proxies {
                if member == RouteDirect || member == RouteBlocked { continue }
                let resolved = proxies.contains(where: { $0.name == member }) || groups.contains(where: { $0.name == member })
                if !resolved {
                    issues.append(YAMLValidationIssue(line: findLine(forGroup: group, member: member, top: top) ?? 0, field: "proxy-groups", reason: "Group '\(group.name)' references unknown proxy or group '\(member)'."))
                }
            }
        }
        for rule in rules {
            if rule.target == RouteDirect || rule.target == RouteBlocked { continue }
            let resolved = proxies.contains(where: { $0.name == rule.target }) || groups.contains(where: { $0.name == rule.target })
            if !resolved {
                issues.append(YAMLValidationIssue(line: findLine(forRule: rule, top: top) ?? 0, field: "rules", reason: "Rule '\(rule.type.rawValue)' references unknown proxy or group '\(rule.target)'."))
            }
        }

        if !issues.isEmpty {
            throw YAMLParsingError.validation(issues)
        }

        let config = ProxyConfiguration(proxies: proxies, groups: groups, rules: rules, schemaVersion: 1, revision: 0)
        return YAMLImportSummary(
            proxiesCount: proxies.count,
            groupsCount: groups.count,
            rulesCount: rules.count,
            skippedProxies: skippedProxies,
            skippedRules: skippedRules,
            warnings: warnings,
            configuration: config
        )
    }

    private static func isNetworkPayloadValid(_ payload: String) -> Bool {
        let upper = payload.uppercased()
        if upper == "TCP" || upper == "UDP" || upper == "TCP,UDP" || upper == "UDP,TCP" {
            return true
        }
        return isIPAddress(payload) || isCIDR(payload)
    }

    private static func isIPAddress(_ value: String) -> Bool {
        let octets = value.split(separator: ".")
        if octets.count == 4 {
            for octet in octets {
                guard let number = Int(octet), (0...255).contains(number) else { return false }
            }
            return true
        }
        // IPv6: conservative check (hex segments separated by colons).
        if value.contains(":") {
            let segments = value.split(separator: ":")
            for segment in segments where !segment.isEmpty {
                guard segment.count <= 4, segment.allSatisfy({ $0.isHexDigit }) else { return false }
            }
            return true
        }
        return false
    }

    private static func isCIDR(_ value: String) -> Bool {
        guard let slash = value.firstIndex(of: "/") else { return false }
        let address = String(value[value.startIndex..<slash])
        let prefix = String(value[value.index(after: slash)...])
        guard let prefixLength = Int(prefix) else { return false }
        if address.contains(":") {
            return (0...128).contains(prefixLength) && isIPAddress(address)
        }
        return (0...32).contains(prefixLength) && isIPAddress(address)
    }

    // MARK: Line lookup helpers (best-effort, for nicer diagnostics)

    private static func findLine(forGroup group: ProxyGroup, member: String, top: [String: YAMLNode]) -> Int? {
        guard let sequence = top["proxy-groups"]?.sequence else { return nil }
        for node in sequence {
            guard let mapping = node.mapping, mapping["name"]?.scalar == group.name else { continue }
            return node.line
        }
        return nil
    }

    private static func findLine(forRule rule: Rule, top: [String: YAMLNode]) -> Int? {
        guard let sequence = top["rules"]?.sequence else { return nil }
        for node in sequence where node.scalar?.contains(rule.target) == true {
            return node.line
        }
        return nil
    }
}