import Foundation
import Network

// MARK: - Routing Model

public enum ProxyProtocol: Equatable {
    case tcp
    case udp
}

/// Result of resolving a group reference. `noMembers` means the group has no
/// currently resolvable member (empty list, all members unresolvable, or a
/// missing selection for a `select` group).
public enum GroupResolveResult: Equatable {
    case proxy(SOCKS5Proxy)
    case direct
    case blocked
    case noMembers
}

/// Final routing decision for a single connection / datagram.
public enum RouteResolution: Equatable {
    case proxy(SOCKS5Proxy)
    case direct
    case blocked
    case failed(String)
}

// MARK: - Address Matching

/// Pure IPv4/IPv6/CIDR matching helpers, independent of the network stack so
/// they can be unit-tested hermetically.
public enum NetworkAddressMatcher {

    public static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        for part in parts {
            guard let value = Int(part), (0...255).contains(value) else { return false }
        }
        return true
    }

    public static func isIPv6(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(":") else { return false }
        // Must not contain a port or zone suffix in our contexts.
        if trimmed.contains("%") { return false }
        // Split on "::" (at most one).
        let halves = trimmed.components(separatedBy: "::")
        guard halves.count <= 2 else { return false }
        let left = halves[0].isEmpty ? [] : halves[0].split(separator: ":")
        let right = halves.count == 2 && !halves[1].isEmpty ? halves[1].split(separator: ":") : []
        for group in left + right {
            guard group.count <= 4, group.allSatisfy({ $0.isHexDigit }) else { return false }
        }
        let total = left.count + right.count
        if halves.count == 2 {
            return total < 8 // "::" must replace at least one group
        }
        return total == 8
    }

    public static func isIPAddress(_ host: String) -> Bool {
        return isIPv4(host) || isIPv6(host)
    }

    public static func isCIDR(_ value: String) -> Bool {
        guard let slash = value.firstIndex(of: "/") else { return false }
        let address = String(value[value.startIndex..<slash])
        let prefix = String(value[value.index(after: slash)...])
        guard let prefixLength = Int(prefix) else { return false }
        if address.contains(":") {
            return (0...128).contains(prefixLength) && isIPv6(address)
        }
        return (0...32).contains(prefixLength) && isIPv4(address)
    }

    /// True when `address` (IPv4 or IPv6 literal) is inside `cidr`.
    public static func cidrContains(address: String, cidr: String) -> Bool {
        guard let slash = cidr.firstIndex(of: "/") else { return false }
        let network = String(cidr[cidr.startIndex..<slash])
        guard let prefixLength = Int(cidr[cidr.index(after: slash)...]) else { return false }

        if isIPv4(address), isIPv4(network) {
            guard (0...32).contains(prefixLength) else { return false }
            let addressValue = ipv4ToUInt32(address)
            let networkValue = ipv4ToUInt32(network)
            let mask: UInt32 = prefixLength == 0 ? 0 : (~UInt32(0)) << UInt32(32 - prefixLength)
            return (addressValue & mask) == (networkValue & mask)
        }
        if isIPv6(address), isIPv6(network) {
            guard (0...128).contains(prefixLength) else { return false }
            let addressBytes = ipv6ToBytes(address)
            let networkBytes = ipv6ToBytes(network)
            guard let a = addressBytes, let n = networkBytes else { return false }
            let fullBytes = prefixLength / 8
            let remainderBits = prefixLength % 8
            for index in 0..<16 {
                var aByte = a[index]
                var nByte = n[index]
                if index < fullBytes {
                    if aByte != nByte { return false }
                    continue
                }
                if remainderBits == 0 { break }
                if index == fullBytes {
                    let mask = UInt8(0xFF) << UInt8(8 - remainderBits)
                    aByte = aByte & mask
                    nByte = nByte & mask
                    if aByte != nByte { return false }
                    break
                }
            }
            return true
        }
        return false
    }

    public static func ipv4ToUInt32(_ address: String) -> UInt32 {
        var result: UInt32 = 0
        for part in address.split(separator: ".") {
            guard let value = UInt32(part) else { return 0 }
            result = (result << 8) | (value & 0xFF)
        }
        return result
    }

    public static func ipv6ToBytes(_ address: String) -> [UInt8]? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        let halves = trimmed.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }
        let left = halves[0].isEmpty ? [] : halves[0].split(separator: ":")
        let right = halves.count == 2 && !halves[1].isEmpty ? halves[1].split(separator: ":") : []
        let missing = 8 - left.count - right.count
        guard halves.count == 2 ? missing >= 1 : missing == 0 else { return nil }
        guard missing >= 0 else { return nil }

        var bytes: [UInt8] = []
        for group in left + Array(repeating: Substring("0"), count: missing) + right {
            guard let value = UInt16(group, radix: 16) else { return nil }
            bytes.append(UInt8((value >> 8) & 0xFF))
            bytes.append(UInt8(value & 0xFF))
        }
        return bytes.count == 16 ? bytes : nil
    }

    /// Formats 16 raw bytes as an IPv6 address string.
    public static func ipv6String(fromBytes data: Data) -> String {
        var groups: [String] = []
        for index in stride(from: 0, to: min(data.count, 16) - 1, by: 2) {
            let value = (UInt16(data[data.startIndex + index]) << 8) | UInt16(data[data.startIndex + index + 1])
            groups.append(String(value, radix: 16))
        }
        while groups.count < 8 {
            groups.append("0")
        }
        return groups.joined(separator: ":")
    }

    /// Encodes a dotted-quad IPv4 string as 4 bytes, or nil.
    public static func ipv4StringToBytes(_ address: String) -> Data? {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var bytes = Data()
        for part in parts {
            guard let value = UInt8(part) else { return nil }
            bytes.append(value)
        }
        return bytes
    }

    /// Encodes an IPv6 string as 16 bytes, or nil.
    public static func ipv6StringToBytes(_ address: String) -> Data? {
        guard let bytes = ipv6ToBytes(address) else { return nil }
        return Data(bytes)
    }
}

// MARK: - Local SOCKS5 Dispatcher

/// Loopback SOCKS5 dispatcher used by the Packet Tunnel.
///
/// Wire-format contract:
///  - RFC 1928 greeting: version 5, method negotiation. The dispatcher offers
///    NO_AUTH and, when local auth is enabled, USERNAME/PASSWORD (RFC 1929).
///    If the client does not offer a method we accept, we answer 0xFF.
///  - CONNECT and UDP ASSOCIATE only; other commands get REP 0x07.
///  - Reply codes: 0x00 success, 0x01 general failure, 0x02 not allowed (BLOCK),
///    0x04 host unreachable, 0x05 connection refused, 0x07 command not supported,
///    0x08 address type not supported.
///  - UDP ASSOCIATE datagrams: RSV(2) FRAG(1) ATYP ADDR PORT PAYLOAD; FRAG != 0
///    is dropped (fragmentation is not supported).
///
/// Routing contract (fail-closed):
///  - rules are evaluated in order; the first match wins;
///  - DOMAIN-SUFFIX matches at label boundaries (`google.com` matches
///    `google.com` and `maps.google.com`, never `evilgoogle.com`);
///  - NETWORK rules match protocol tokens (TCP / UDP / TCP,UDP) or IP/CIDR
///    payloads against the destination address;
///  - a rule can target DIRECT, BLOCK or any proxy/group by name;
///  - when no rule matches, the fallback is the selected group, then the
///    selected proxy; with no selection at all the route is BLOCKED (never an
///    implicit DIRECT);
///  - unresolvable routes are answered with REP 0x02/0x01 and closed.
public final class LocalProxyServer {

    public let port: UInt16
    private let settings: SharedSettings
    private let credentialStore: CredentialStore
    private var listener: NWListener?

    public var config: ProxyConfiguration?
    public private(set) var selectedProxyName: String = ""
    public private(set) var selectedGroupName: String = ""

    /// Optional async resolver (hostname -> IP literals). Used to evaluate
    /// NETWORK/IP/CIDR rules against domain destinations. The provider wires
    /// `ProxyEndpointResolver` here.
    public var hostResolver: ((String, @escaping ([String]) -> Void) -> Void)?

    // Per-connection queues: rule evaluation may block on resolution, and
    // blocking must never stall the shared dispatcher queue.
    private let stateQueue = DispatchQueue(label: "com.rakib.tunnexa.localproxy.state")
    private let listenerQueue = DispatchQueue(label: "com.rakib.tunnexa.localproxy.listener")
    private var connectionCounter = 0
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    // Load-balancer state.
    private var loadBalanceIndices: [String: Int] = [:]
    private var loadBalanceSignatures: [String: String] = [:]
    private let loadBalanceQueue = DispatchQueue(label: "com.rakib.tunnexa.localproxy.lb")

    // UDP associations (keyed by client TCP connection).
    private var udpAssociations: [ObjectIdentifier: UDPAssociation] = [:]
    private let udpQueue = DispatchQueue(label: "com.rakib.tunnexa.localproxy.udp")

    public init(port: UInt16, settings: SharedSettings, credentialStore: CredentialStore? = nil) {
        self.port = port
        self.settings = settings
        self.credentialStore = credentialStore ?? KeychainHelper.shared
        loadConfig()
    }

    // MARK: - Configuration

    public func loadConfig() {
        config = settings.loadConfiguration()
        selectedProxyName = settings.selectedProxyName
        selectedGroupName = settings.selectedGroupName
        resetLoadBalancerIfNeeded()
    }

    // MARK: - Lifecycle

    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "Tunnexa.Dispatcher", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid listener port: \(port)"])
        }
        let listener = try NWListener(using: parameters, on: nwPort)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                SharedLogging.log("Local SOCKS5 Dispatcher ready on port \(self.port).", category: .routing)
            case .failed(let error):
                SharedLogging.log("Local SOCKS5 Dispatcher failed: \(error.localizedDescription)", category: .routing, level: .error)
            case .cancelled:
                break
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener.start(queue: listenerQueue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        udpQueue.sync {
            for association in udpAssociations.values {
                association.shutdown()
            }
            udpAssociations.removeAll()
        }
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
        SharedLogging.log("Local SOCKS5 Dispatcher stopped.", category: .routing)
    }

    // MARK: - TCP Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connectionCounter += 1
        let id = ObjectIdentifier(connection)
        let connectionQueue = DispatchQueue(label: "com.rakib.tunnexa.localproxy.conn.\(connectionCounter)")
        activeConnections[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled:
                self?.activeConnections.removeValue(forKey: id)
            case .failed:
                self?.activeConnections.removeValue(forKey: id)
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
        readGreeting(connection, queue: connectionQueue)
    }

    // MARK: Greeting (RFC 1928)

    private func readGreeting(_ connection: NWConnection, queue: DispatchQueue) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 2, error == nil else {
                connection.cancel()
                return
            }
            guard data[0] == 5 else {
                // Only SOCKS5 is supported; no version-negotiation fallback.
                connection.cancel()
                return
            }
            let numMethods = Int(data[1])
            guard numMethods > 0 else {
                connection.cancel()
                return
            }
            connection.receive(minimumIncompleteLength: numMethods, maximumLength: numMethods) { [weak self] methodsData, _, _, error in
                guard let self = self, let methodsData = methodsData, methodsData.count == numMethods, error == nil else {
                    connection.cancel()
                    return
                }
                self.negotiateMethod(connection, methods: methodsData, queue: queue)
            }
        }
    }

    private func negotiateMethod(_ connection: NWConnection, methods: Data, queue: DispatchQueue) {
        let authEnabled = settings.bool(SettingsKey.localAuthEnabled)
        var offersNoAuth = false
        var offersUserPass = false
        for method in methods {
            if method == 0 { offersNoAuth = true }
            if method == 2 { offersUserPass = true }
        }

        let chosenMethod: UInt8
        if authEnabled {
            guard offersUserPass else {
                // We require auth; the client does not offer it.
                connection.send(content: Data([5, 0xFF]), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            chosenMethod = 2
        } else {
            guard offersNoAuth else {
                connection.send(content: Data([5, 0xFF]), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            chosenMethod = 0
        }

        connection.send(content: Data([5, chosenMethod]), completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                connection.cancel()
                return
            }
            if chosenMethod == 2 {
                self?.readUserPassAuth(connection, queue: queue)
            } else {
                self?.readRequest(connection, queue: queue)
            }
        })
    }

    // MARK: RFC 1929 local authentication

    private func readUserPassAuth(_ connection: NWConnection, queue: DispatchQueue) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 2, data[0] == 1, error == nil else {
                connection.cancel()
                return
            }
            let usernameLength = Int(data[1])
            guard usernameLength > 0 else {
                self.replyAuthFailure(connection)
                return
            }
            connection.receive(minimumIncompleteLength: usernameLength, maximumLength: usernameLength) { [weak self] usernameData, _, _, error in
                guard let self = self, let usernameData = usernameData, usernameData.count == usernameLength, error == nil else {
                    connection.cancel()
                    return
                }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] passLenData, _, _, error in
                    guard let self = self, let passLenData = passLenData, passLenData.count == 1, error == nil else {
                        connection.cancel()
                        return
                    }
                    let passwordLength = Int(passLenData[0])
                    connection.receive(minimumIncompleteLength: passwordLength, maximumLength: passwordLength) { [weak self] passwordData, _, _, error in
                        guard let self = self, let passwordData = passwordData, passwordData.count == passwordLength, error == nil else {
                            connection.cancel()
                            return
                        }
                        self.verifyLocalAuth(connection, usernameData: usernameData, passwordData: passwordData, queue: queue)
                    }
                }
            }
        }
    }

    private func verifyLocalAuth(_ connection: NWConnection, usernameData: Data, passwordData: Data, queue: DispatchQueue) {
        let expectedUsername = settings.string(SettingsKey.localAuthUsername) ?? ""
        let expectedPassword = settings.string(SettingsKey.localAuthPassword) ?? ""
        let usernameOK = constantTimeEquals(usernameData, Data(expectedUsername.utf8))
        let passwordOK = constantTimeEquals(passwordData, Data(expectedPassword.utf8))

        guard usernameOK && passwordOK else {
            SharedLogging.log("Local dispatcher authentication failed (username mismatch: \(usernameOK)).", category: .security, level: .warning)
            replyAuthFailure(connection)
            return
        }
        connection.send(content: Data([1, 0]), completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                connection.cancel()
                return
            }
            self?.readRequest(connection, queue: queue)
        })
    }

    private func replyAuthFailure(_ connection: NWConnection) {
        connection.send(content: Data([1, 1]), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for index in 0..<lhs.count {
            diff |= lhs[lhs.startIndex + index] ^ rhs[rhs.startIndex + index]
        }
        return diff == 0
    }

    // MARK: Request parsing

    private func readRequest(_ connection: NWConnection, queue: DispatchQueue) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 4, error == nil else {
                connection.cancel()
                return
            }
            let version = data[0]
            let command = data[1]
            let atyp = data[3]
            guard version == 5 else {
                connection.cancel()
                return
            }

            switch command {
            case 0x01, 0x03:
                break
            default:
                // Command not supported.
                self.sendReply(connection, code: 0x07)
                return
            }

            switch atyp {
            case 1: // IPv4
                connection.receive(minimumIncompleteLength: 6, maximumLength: 6) { [weak self] addrData, _, _, error in
                    guard let self = self, let addrData = addrData, addrData.count == 6, error == nil else {
                        connection.cancel()
                        return
                    }
                    let host = "\(addrData[0]).\(addrData[1]).\(addrData[2]).\(addrData[3])"
                    let port = (Int(addrData[4]) << 8) | Int(addrData[5])
                    self.handleRequest(connection, command: command, host: host, port: port, queue: queue)
                }
            case 3: // Domain name
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] lenData, _, _, error in
                    guard let self = self, let lenData = lenData, lenData.count == 1, error == nil else {
                        connection.cancel()
                        return
                    }
                    let length = Int(lenData[0])
                    guard length > 0 else {
                        self.sendReply(connection, code: 0x01)
                        return
                    }
                    connection.receive(minimumIncompleteLength: length + 2, maximumLength: length + 2) { [weak self] domainData, _, _, error in
                        guard let self = self, let domainData = domainData, domainData.count == length + 2, error == nil else {
                            connection.cancel()
                            return
                        }
                        let host = String(data: domainData.subdata(in: 0..<length), encoding: .utf8) ?? ""
                        let port = (Int(domainData[length]) << 8) | Int(domainData[length + 1])
                        self.handleRequest(connection, command: command, host: host, port: port, queue: queue)
                    }
                }
            case 4: // IPv6
                connection.receive(minimumIncompleteLength: 18, maximumLength: 18) { [weak self] addrData, _, _, error in
                    guard let self = self, let addrData = addrData, addrData.count == 18, error == nil else {
                        connection.cancel()
                        return
                    }
                    let host = NetworkAddressMatcher.ipv6String(fromBytes: addrData.subdata(in: 0..<16))
                    let port = (Int(addrData[16]) << 8) | Int(addrData[17])
                    self.handleRequest(connection, command: command, host: host, port: port, queue: queue)
                }
            default:
                // Address type not supported.
                self.sendReply(connection, code: 0x08)
            }
        }
    }

    private func handleRequest(_ connection: NWConnection, command: UInt8, host: String, port: Int, queue: DispatchQueue) {
        loadConfig()
        guard (1...65535).contains(port) else {
            sendReply(connection, code: 0x01)
            return
        }

        let protocolType: ProxyProtocol = (command == 0x03) ? .udp : .tcp
        let route = resolveRoute(host: host, port: port, protocolType: protocolType)

        switch command {
        case 0x01: // CONNECT
            handleConnect(connection, host: host, port: port, route: route, queue: queue)
        case 0x03: // UDP ASSOCIATE
            handleUDPAssociate(connection, route: route, queue: queue)
        default:
            sendReply(connection, code: 0x07)
        }
    }

    // MARK: - Routing (testable)

    /// Evaluates rules and the selection fallback. Returns the target name
    /// (proxy or group name, or DIRECT / BLOCK), or nil when there is no
    /// usable selection.
    public func evaluateRules(host: String, port: Int, protocolType: ProxyProtocol, resolvedAddresses: [String] = []) -> String? {
        let normalizedHost = canonicalizeHost(host)
        guard let config = config else {
            return fallbackTarget()
        }

        let protocolToken: String? = {
            switch protocolType {
            case .tcp: return "TCP"
            case .udp: return "UDP"
            }
        }()
        let candidateAddresses = resolvedAddresses.isEmpty ? [normalizedHost] : resolvedAddresses

        for rule in config.rules {
            switch rule.type {
            case .domainSuffix:
                guard let suffix = rule.payload?.lowercased(), !suffix.isEmpty else { continue }
                let hostLower = normalizedHost.lowercased()
                if hostLower == suffix || hostLower.hasSuffix("." + suffix) {
                    return rule.target
                }
            case .domainKeyword:
                guard let keyword = rule.payload?.lowercased(), !keyword.isEmpty else { continue }
                if normalizedHost.lowercased().contains(keyword) {
                    return rule.target
                }
            case .domain:
                guard let targetHost = rule.payload?.lowercased(), !targetHost.isEmpty else { continue }
                if normalizedHost.lowercased() == targetHost {
                    return rule.target
                }
            case .network:
                guard let payload = rule.payload else { continue }
                let trimmed = payload.trimmingCharacters(in: .whitespaces).uppercased()
                let protocolMatch = trimmed == "TCP" || trimmed == "UDP" || trimmed == "TCP,UDP" || trimmed == "UDP,TCP"
                if protocolMatch, trimmed.contains(protocolToken ?? "") {
                    return rule.target
                }
                if NetworkAddressMatcher.isCIDR(payload) || NetworkAddressMatcher.isIPAddress(payload) {
                    for address in candidateAddresses {
                        if NetworkAddressMatcher.isCIDR(payload), NetworkAddressMatcher.cidrContains(address: address, cidr: payload) {
                            return rule.target
                        }
                        if NetworkAddressMatcher.isIPAddress(payload), address == payload {
                            return rule.target
                        }
                    }
                }
            case .match:
                return rule.target
            }
        }
        return fallbackTarget()
    }

    private func fallbackTarget() -> String? {
        if !selectedGroupName.isEmpty {
            return selectedGroupName
        }
        if !selectedProxyName.isEmpty {
            return selectedProxyName
        }
        return nil
    }

    /// Resolves a target name (DIRECT / BLOCK / proxy / group) into a route.
    public func resolveTarget(_ target: String) -> RouteResolution {
        if target == RouteDirect { return .direct }
        if target == RouteBlocked { return .blocked }
        guard let config = config else {
            return .failed("No configuration loaded")
        }
        if let proxy = config.proxies.first(where: { $0.name == target }) {
            return .proxy(proxy)
        }
        if let group = config.groups.first(where: { $0.name == target }) {
            switch resolveGroup(group) {
            case .proxy(let proxy):
                return .proxy(proxy)
            case .direct:
                return .direct
            case .blocked:
                return .blocked
            case .noMembers:
                return .failed("Group '\(target)' has no resolvable members")
            }
        }
        return .failed("Unknown proxy or group '\(target)'")
    }

    /// Full routing decision for a connection or datagram.
    public func resolveRoute(host: String, port: Int, protocolType: ProxyProtocol) -> RouteResolution {
        // Resolve domain destinations once when IP-scoped rules exist.
        var resolvedAddresses: [String] = []
        if !NetworkAddressMatcher.isIPAddress(host) {
            resolvedAddresses = synchronousResolution(host)
        }
        if let target = evaluateRules(host: host, port: port, protocolType: protocolType, resolvedAddresses: resolvedAddresses) {
            return resolveTarget(target)
        }
        return .blocked
    }

    /// Resolves a group according to its type. Testable and race-free.
    public func resolveGroup(_ group: ProxyGroup) -> GroupResolveResult {
        return resolveGroup(group, visited: [], depth: 0)
    }

    private func resolveGroup(_ group: ProxyGroup, visited: Set<String>, depth: Int) -> GroupResolveResult {
        guard depth < 8 else {
            SharedLogging.log("Group resolution exceeded depth limit at '\(group.name)'.", category: .routing, level: .error)
            return .noMembers
        }
        var visited = visited
        guard !visited.contains(group.name) else {
            SharedLogging.log("Circular group reference detected at '\(group.name)'.", category: .routing, level: .error)
            return .noMembers
        }
        visited.insert(group.name)

        switch group.type {
        case .select:
            let option = settings.selectedGroupOption(for: group.name) ?? group.proxies.first ?? ""
            if option.isEmpty { return .noMembers }
            return resolveOption(option, visited: visited, depth: depth)

        case .loadBalance:
            let members = group.proxies
            guard !members.isEmpty else { return .noMembers }
            if group.strategy == "round-robin" {
                return resolveRoundRobin(group, visited: visited, depth: depth)
            }
            if let first = members.first {
                return resolveOption(first, visited: visited, depth: depth)
            }
            return .noMembers
        }
    }

    private func resolveRoundRobin(_ group: ProxyGroup, visited: Set<String>, depth: Int) -> GroupResolveResult {
        let members = group.proxies
        let signature = members.joined(separator: "\u{1F}")

        let startIndex: Int = loadBalanceQueue.sync {
            if loadBalanceSignatures[group.name] != signature {
                loadBalanceSignatures[group.name] = signature
                loadBalanceIndices[group.name] = 0
            }
            let current = loadBalanceIndices[group.name] ?? 0
            loadBalanceIndices[group.name] = (current + 1) % members.count
            return current
        }

        // Skip unresolvable members (DIRECT/BLOCK/missing) by scanning forward.
        for offset in 0..<members.count {
            let index = (startIndex + offset) % members.count
            let result = resolveOption(members[index], visited: visited, depth: depth)
            switch result {
            case .proxy, .direct, .blocked:
                return result
            case .noMembers:
                continue
            }
        }
        return .noMembers
    }

    private func resolveOption(_ option: String, visited: Set<String>, depth: Int) -> GroupResolveResult {
        if option == RouteDirect { return .direct }
        if option == RouteBlocked { return .blocked }
        guard let config = config else { return .noMembers }
        if let proxy = config.proxies.first(where: { $0.name == option }) {
            return .proxy(proxy)
        }
        if let group = config.groups.first(where: { $0.name == option }) {
            return resolveGroup(group, visited: visited, depth: depth + 1)
        }
        return .noMembers
    }

    private func resetLoadBalancerIfNeeded() {
        guard let groups = config?.groups else { return }
        loadBalanceQueue.sync {
            for group in groups {
                let signature = group.proxies.joined(separator: "\u{1F}")
                if loadBalanceSignatures[group.name] != signature {
                    loadBalanceSignatures[group.name] = signature
                    loadBalanceIndices[group.name] = 0
                }
            }
        }
    }

    // MARK: - CONNECT

    private func handleConnect(_ connection: NWConnection, host: String, port: Int, route: RouteResolution, queue: DispatchQueue) {
        switch route {
        case .direct:
            connectDirect(connection, host: host, port: port, queue: queue)
        case .proxy(let proxy):
            connectViaProxy(connection, proxy: proxy, targetHost: host, targetPort: port, queue: queue)
        case .blocked:
            SharedLogging.log("Routing policy: BLOCKED destination \(host):\(port).", category: .routing)
            sendReply(connection, code: 0x02)
        case .failed(let reason):
            SharedLogging.log("Routing failed for \(host):\(port): \(reason)", category: .routing, level: .error)
            sendReply(connection, code: 0x01)
        }
    }

    private func connectDirect(_ clientConnection: NWConnection, host: String, port: Int, queue: DispatchQueue) {
        guard let endpoint = makeEndpoint(host: host, port: port) else {
            sendReply(clientConnection, code: 0x01)
            return
        }
        let destination = NWConnection(to: endpoint, using: .tcp)
        destination.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.sendReply(clientConnection, code: 0x00)
                self.bridgeConnections(clientConnection, destination, queue: queue)
            case .failed(let error):
                SharedLogging.log("Direct connection to \(host):\(port) failed: \(error.localizedDescription)", category: .network, level: .error)
                self.sendReply(clientConnection, code: 0x05)
            default:
                break
            }
        }
        destination.start(queue: queue)
    }

    private func connectViaProxy(_ clientConnection: NWConnection, proxy: SOCKS5Proxy, targetHost: String, targetPort: Int, queue: DispatchQueue) {
        guard let endpoint = makeEndpoint(host: proxy.host, port: proxy.port) else {
            sendReply(clientConnection, code: 0x01)
            return
        }
        let upstream = NWConnection(to: endpoint, using: .tcp)
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.performUpstreamHandshake(upstream, proxy: proxy, targetHost: targetHost, targetPort: targetPort, queue: queue) { success in
                    if success {
                        self.sendReply(clientConnection, code: 0x00)
                        self.bridgeConnections(clientConnection, upstream, queue: queue)
                    } else {
                        SharedLogging.log("Upstream SOCKS5 handshake with \(proxy.name) failed.", category: .proxy, level: .error)
                        self.sendReply(clientConnection, code: 0x05)
                        upstream.cancel()
                    }
                }
            case .failed(let error):
                SharedLogging.log("Connection to proxy \(proxy.name) (\(proxy.host):\(proxy.port)) failed: \(error.localizedDescription)", category: .proxy, level: .error)
                self.sendReply(clientConnection, code: 0x04)
            default:
                break
            }
        }
        upstream.start(queue: queue)
    }

    private func performUpstreamHandshake(_ connection: NWConnection, proxy: SOCKS5Proxy, targetHost: String, targetPort: Int, queue: DispatchQueue, completion: @escaping (Bool) -> Void) {
        let resolvedPassword = proxy.password ?? credentialStore.loadPassword(forProxyId: proxy.id.uuidString)
        var methods: [UInt8] = [0]
        if proxy.username != nil {
            methods.append(2)
        }

        let greeting = Data([5, UInt8(methods.count)] + methods)
        connection.send(content: greeting, completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                completion(false)
                return
            }
            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, _, _, error in
                guard let self = self, let data = data, data.count == 2, error == nil else {
                    completion(false)
                    return
                }
                guard data[0] == 5 else {
                    completion(false)
                    return
                }
                switch data[1] {
                case 0:
                    self.sendUpstreamConnect(connection, targetHost: targetHost, targetPort: targetPort, completion: completion)
                case 2:
                    guard let username = proxy.username else {
                        completion(false)
                        return
                    }
                    self.performUpstreamAuth(connection, username: username, password: resolvedPassword ?? "", completion: { success in
                        if success {
                            self.sendUpstreamConnect(connection, targetHost: targetHost, targetPort: targetPort, completion: completion)
                        } else {
                            completion(false)
                        }
                    })
                default:
                    SharedLogging.log("Upstream proxy rejected offered authentication methods (selected 0x\(String(format: "%02x", data[1]))).", category: .proxy, level: .warning)
                    completion(false)
                }
            }
        })
    }

    private func performUpstreamAuth(_ connection: NWConnection, username: String, password: String, completion: @escaping (Bool) -> Void) {
        let usernameBytes = Array(username.utf8)
        let passwordBytes = Array(password.utf8)
        guard usernameBytes.count <= 255, passwordBytes.count <= 255 else {
            completion(false)
            return
        }
        var auth = Data()
        auth.append(1)
        auth.append(UInt8(usernameBytes.count))
        auth.append(contentsOf: usernameBytes)
        auth.append(UInt8(passwordBytes.count))
        auth.append(contentsOf: passwordBytes)

        connection.send(content: auth, completion: .contentProcessed { error in
            guard error == nil else {
                completion(false)
                return
            }
            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
                guard let data = data, data.count == 2, error == nil, data[0] == 1 else {
                    completion(false)
                    return
                }
                completion(data[1] == 0)
            }
        })
    }

    private func sendUpstreamConnect(_ connection: NWConnection, targetHost: String, targetPort: Int, completion: @escaping (Bool) -> Void) {
        var request = Data([5, 1, 0])
        if let ipv4 = NetworkAddressMatcher.ipv4StringToBytes(targetHost) {
            request.append(1)
            request.append(ipv4)
        } else if let ipv6 = NetworkAddressMatcher.ipv6StringToBytes(targetHost) {
            request.append(4)
            request.append(ipv6)
        } else {
            let domainBytes = Array(targetHost.utf8)
            guard !domainBytes.isEmpty, domainBytes.count <= 255 else {
                completion(false)
                return
            }
            request.append(3)
            request.append(UInt8(domainBytes.count))
            request.append(contentsOf: domainBytes)
        }
        request.append(UInt8((targetPort >> 8) & 0xFF))
        request.append(UInt8(targetPort & 0xFF))

        connection.send(content: request, completion: .contentProcessed { error in
            guard error == nil else {
                completion(false)
                return
            }
            self.readUpstreamReply(connection, completion: completion)
        })
    }

    private func readUpstreamReply(_ connection: NWConnection, completion: @escaping (Bool) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, error in
            guard let data = data, data.count == 4, error == nil else {
                completion(false)
                return
            }
            guard data[1] == 0 else {
                SharedLogging.log("Upstream proxy rejected CONNECT (code 0x\(String(format: "%02x", data[1]))).", category: .proxy, level: .warning)
                completion(false)
                return
            }
            let atyp = data[3]
            var remaining = 0
            switch atyp {
            case 1: remaining = 6
            case 4: remaining = 18
            case 3:
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { lenData, _, _, error in
                    guard let lenData = lenData, lenData.count == 1, error == nil else {
                        completion(false)
                        return
                    }
                    let length = Int(lenData[0])
                    connection.receive(minimumIncompleteLength: length + 2, maximumLength: length + 2) { _, _, _, error in
                        completion(error == nil)
                    }
                }
                return
            default:
                completion(false)
                return
            }
            connection.receive(minimumIncompleteLength: remaining, maximumLength: remaining) { _, _, _, error in
                completion(error == nil)
            }
        }
    }

    // MARK: - Reply helpers

    /// SOCKS5 reply: VER REP RSV ATYP(IPv4) BND.ADDR BND.PORT.
    /// BND is 127.0.0.1:0 for CONNECT (we do not maintain a bound address),
    /// or 127.0.0.1:<relayPort> for UDP ASSOCIATE.
    private func sendReply(_ connection: NWConnection, code: UInt8, relayPort: UInt16? = nil) {
        var reply = Data([5, code, 0, 1, 127, 0, 0, 1])
        let boundPort = relayPort ?? 0
        reply.append(UInt8((boundPort >> 8) & 0xFF))
        reply.append(UInt8(boundPort & 0xFF))
        connection.send(content: reply, completion: .contentProcessed { _ in })
    }

    // MARK: - Data bridge (TCP)

    private func bridgeConnections(_ conn1: NWConnection, _ conn2: NWConnection, queue: DispatchQueue) {
        pipe(from: conn1, to: conn2, queue: queue)
        pipe(from: conn2, to: conn1, queue: queue)
    }

    private func pipe(from: NWConnection, to: NWConnection, queue: DispatchQueue) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { [weak self] sendError in
                    if sendError == nil {
                        if isComplete {
                            to.send(content: nil, contentContext: .defaultStream, isComplete: true, completion: .idempotent)
                        } else {
                            self?.pipe(from: from, to: to, queue: queue)
                        }
                    } else {
                        from.cancel()
                        to.cancel()
                    }
                })
            } else {
                if isComplete {
                    to.send(content: nil, contentContext: .defaultStream, isComplete: true, completion: .idempotent)
                }
                if error != nil {
                    from.cancel()
                    to.cancel()
                }
            }
        }
    }

    // MARK: - UDP ASSOCIATE

    private func handleUDPAssociate(_ clientConnection: NWConnection, route: RouteResolution, queue: DispatchQueue) {
        switch route {
        case .blocked:
            SharedLogging.log("Routing policy: BLOCKED UDP association.", category: .routing)
            sendReply(clientConnection, code: 0x02)
        case .failed(let reason):
            SharedLogging.log("UDP association failed: \(reason)", category: .routing, level: .error)
            sendReply(clientConnection, code: 0x01)
        case .direct, .proxy:
            do {
                let parameters = NWParameters.udp
                parameters.requiredInterfaceType = .loopback
                let udpListener = try NWListener(using: parameters, on: .any)

                let association = UDPAssociation(clientConnection: clientConnection, route: route, credentialStore: credentialStore)
                let associationID = ObjectIdentifier(clientConnection)
                udpQueue.sync {
                    udpAssociations[associationID] = association
                }

                udpListener.stateUpdateHandler = { [weak self] state in
                    guard let self = self else { return }
                    if case .ready = state {
                        let assignedPort = udpListener.port?.rawValue ?? 0
                        self.sendReply(clientConnection, code: 0x00, relayPort: assignedPort)
                    }
                }
                udpListener.newConnectionHandler = { [weak self] udpConnection in
                    self?.handleUDPClientConnection(udpConnection, association: association, queue: queue)
                }
                udpListener.start(queue: queue)

                clientConnection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .cancelled, .failed:
                        self?.teardownUDPAssociation(id: associationID, listener: udpListener)
                    default:
                        break
                    }
                }
            } catch {
                sendReply(clientConnection, code: 0x01)
            }
        }
    }

    private func teardownUDPAssociation(id: ObjectIdentifier, listener: NWListener) {
        udpQueue.sync {
            udpAssociations.removeValue(forKey: id)?.shutdown()
        }
        listener.cancel()
    }

    private func handleUDPClientConnection(_ clientUDPConn: NWConnection, association: UDPAssociation, queue: DispatchQueue) {
        clientUDPConn.start(queue: queue)
        association.attach(clientUDPConn)
        association.scheduleIdleTimer()
        receiveClientDatagram(clientUDPConn, association: association, queue: queue)
    }

    private func receiveClientDatagram(_ clientUDPConn: NWConnection, association: UDPAssociation, queue: DispatchQueue) {
        clientUDPConn.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                association.remove(clientUDPConn)
                return
            }
            self.dispatchClientDatagram(data, clientUDPConn: clientUDPConn, association: association, queue: queue)
            self.receiveClientDatagram(clientUDPConn, association: association, queue: queue)
        }
    }

    private func dispatchClientDatagram(_ data: Data, clientUDPConn: NWConnection, association: UDPAssociation, queue: DispatchQueue) {
        guard data.count > 4 else { return }
        // RSV(2) FRAG(1) ATYP(1) ...
        let fragment = data[2]
        guard fragment == 0 else {
            SharedLogging.log("UDP datagram with FRAG != 0 dropped (fragmentation unsupported).", category: .routing, level: .warning)
            return
        }
        guard let parsed = parseSOCKS5UDPHeader(data) else { return }
        let payload = data.subdata(in: parsed.headerLength..<data.count)
        let port = parsed.port
        guard (1...65535).contains(port) else { return }

        // Per-datagram rule evaluation.
        let route = resolveRoute(host: parsed.host, port: port, protocolType: .udp)
        association.route = route

        switch route {
        case .direct:
            association.sendDirect(payload: payload, host: parsed.host, port: port, sourceConnection: clientUDPConn, queue: queue)
        case .proxy(let proxy):
            association.ensureRelay(proxy: proxy, queue: queue) { [weak self] success in
                guard success else { return }
                self?.sendRelayPacket(association, payload: payload, host: parsed.host, port: port, sourceConnection: clientUDPConn, queue: queue)
            }
        case .blocked:
            SharedLogging.log("Routing policy: BLOCKED UDP datagram to \(parsed.host):\(port).", category: .routing)
        case .failed(let reason):
            SharedLogging.log("UDP route failed for \(parsed.host):\(port): \(reason)", category: .routing, level: .error)
        }
    }

    private struct UDPHeader {
        let host: String
        let port: Int
        let headerLength: Int
    }

    private func parseSOCKS5UDPHeader(_ data: Data) -> UDPHeader? {
        guard data.count > 4 else { return nil }
        let atyp = data[3]
        switch atyp {
        case 1:
            guard data.count >= 10 else { return nil }
            let host = "\(data[4]).\(data[5]).\(data[6]).\(data[7])"
            let port = (Int(data[8]) << 8) | Int(data[9])
            return UDPHeader(host: host, port: port, headerLength: 10)
        case 3:
            let length = Int(data[4])
            guard length > 0, data.count >= 5 + length + 2 else { return nil }
            guard let host = String(data: data.subdata(in: 5..<(5 + length)), encoding: .utf8), !host.isEmpty else { return nil }
            let port = (Int(data[5 + length]) << 8) | Int(data[5 + length + 1])
            return UDPHeader(host: host, port: port, headerLength: 5 + length + 2)
        case 4:
            guard data.count >= 22 else { return nil }
            let host = NetworkAddressMatcher.ipv6String(fromBytes: data.subdata(in: 4..<20))
            let port = (Int(data[20]) << 8) | Int(data[21])
            return UDPHeader(host: host, port: port, headerLength: 22)
        default:
            return nil
        }
    }

    private func sendRelayPacket(_ association: UDPAssociation, payload: Data, host: String, port: Int, sourceConnection: NWConnection, queue: DispatchQueue) {
        var packet = Data([0, 0, 0])
        if let ipv4 = NetworkAddressMatcher.ipv4StringToBytes(host) {
            packet.append(1)
            packet.append(ipv4)
        } else if let ipv6 = NetworkAddressMatcher.ipv6StringToBytes(host) {
            packet.append(4)
            packet.append(ipv6)
        } else {
            let domainBytes = Array(host.utf8)
            guard !domainBytes.isEmpty, domainBytes.count <= 255 else { return }
            packet.append(3)
            packet.append(UInt8(domainBytes.count))
            packet.append(contentsOf: domainBytes)
        }
        packet.append(UInt8((port >> 8) & 0xFF))
        packet.append(UInt8(port & 0xFF))
        packet.append(payload)

        association.sendToRelay(packet, sourceConnection: sourceConnection, queue: queue)
    }

    private func makeEndpoint(host: String, port: Int) -> NWEndpoint? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        return NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
    }

    // MARK: - DNS resolution bridge

    private func synchronousResolution(_ host: String) -> [String] {
        guard let resolver = hostResolver else { return [] }
        var result: [String] = []
        let semaphore = DispatchSemaphore(value: 0)
        resolver(host) { addresses in
            result = addresses
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
        return result
    }

    // MARK: - Helpers

    private func canonicalizeHost(_ host: String) -> String {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip trailing dot for suffix comparisons.
        while trimmed.hasSuffix(".") && trimmed.count > 1 {
            trimmed.removeLast()
        }
        return trimmed
    }
}

// MARK: - UDP Association

/// One SOCKS5 UDP ASSOCIATE session. Owns the upstream relay connection(s)
/// and the idle timeout, and delivers replies back to the client.
private final class UDPAssociation {

    let clientConnection: NWConnection
    let credentialStore: CredentialStore
    private let idleTimeout: TimeInterval = 60.0

    var route: RouteResolution = .blocked

    private var relayUDP: NWConnection?
    private var directRelays: [String: NWConnection] = [:]
    private var clientConns: [ObjectIdentifier: NWConnection] = [:]
    private var idleTimer: DispatchSourceTimer?
    private var lastActivity = Date()
    private let lock = NSLock()

    init(clientConnection: NWConnection, route: RouteResolution, credentialStore: CredentialStore) {
        self.clientConnection = clientConnection
        self.route = route
        self.credentialStore = credentialStore
    }

    func attach(_ udpConnection: NWConnection) {
        lock.lock()
        clientConns[ObjectIdentifier(udpConnection)] = udpConnection
        lastActivity = Date()
        lock.unlock()
    }

    func remove(_ udpConnection: NWConnection) {
        lock.lock()
        clientConns.removeValue(forKey: ObjectIdentifier(udpConnection))
        let empty = clientConns.isEmpty
        lock.unlock()
        if empty {
            shutdown()
        }
    }

    func scheduleIdleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + idleTimeout, repeating: idleTimeout)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let idle = Date().timeIntervalSince(self.lastActivity) >= self.idleTimeout
            self.lock.unlock()
            if idle {
                self.shutdown()
            }
        }
        lock.lock()
        idleTimer?.cancel()
        idleTimer = timer
        lock.unlock()
        timer.resume()
    }

    private func touchActivity() {
        lock.lock()
        lastActivity = Date()
        lock.unlock()
    }

    /// Sends a payload directly to the destination (direct route), creating a
    /// dedicated UDP connection per destination, and relays the response back.
    func sendDirect(payload: Data, host: String, port: Int, sourceConnection: NWConnection, queue: DispatchQueue) {
        touchActivity()
        let key = "\(host):\(port)"
        var relay: NWConnection?
        lock.lock()
        relay = directRelays[key]
        lock.unlock()

        if let existing = relay {
            sendDirectDatagram(existing, payload: payload, sourceConnection: sourceConnection, host: host, port: port, queue: queue)
            return
        }

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let newRelay = NWConnection(to: endpoint, using: .udp)
        lock.lock()
        directRelays[key] = newRelay
        lock.unlock()

        newRelay.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                self.sendDirectDatagram(newRelay, payload: payload, sourceConnection: sourceConnection, host: host, port: port, queue: queue)
            } else if case .failed = state {
                self.lock.lock()
                self.directRelays.removeValue(forKey: key)
                self.lock.unlock()
            }
        }
        newRelay.start(queue: queue)
    }

    private func sendDirectDatagram(_ relay: NWConnection, payload: Data, sourceConnection: NWConnection, host: String, port: Int, queue: DispatchQueue) {
        relay.send(content: payload, completion: .contentProcessed { [weak self] error in
            guard let self = self, error == nil else { return }
            self.touchActivity()
            relay.receiveMessage { [weak self] responseData, _, _, error in
                guard let self = self, let responseData = responseData, error == nil else { return }
                var response = Data([0, 0, 0])
                if let ipv4 = NetworkAddressMatcher.ipv4StringToBytes(host) {
                    response.append(1)
                    response.append(ipv4)
                } else if let ipv6 = NetworkAddressMatcher.ipv6StringToBytes(host) {
                    response.append(4)
                    response.append(ipv6)
                } else {
                    let domainBytes = Array(host.utf8)
                    guard !domainBytes.isEmpty, domainBytes.count <= 255 else { return }
                    response.append(3)
                    response.append(UInt8(domainBytes.count))
                    response.append(contentsOf: domainBytes)
                }
                response.append(UInt8((port >> 8) & 0xFF))
                response.append(UInt8(port & 0xFF))
                response.append(responseData)
                self.sendToClient(response, sourceConnection: sourceConnection, queue: queue)
                // Continue receiving subsequent replies on the same relay.
                self.receiveDirectReplies(relay, sourceConnection: sourceConnection, host: host, port: port, queue: queue)
            }
        })
    }

    private func receiveDirectReplies(_ relay: NWConnection, sourceConnection: NWConnection, host: String, port: Int, queue: DispatchQueue) {
        relay.receiveMessage { [weak self] responseData, _, _, error in
            guard let self = self, let responseData = responseData, error == nil else { return }
            self.touchActivity()
            var response = Data([0, 0, 0])
            if let ipv4 = NetworkAddressMatcher.ipv4StringToBytes(host) {
                response.append(1)
                response.append(ipv4)
            } else if let ipv6 = NetworkAddressMatcher.ipv6StringToBytes(host) {
                response.append(4)
                response.append(ipv6)
            } else {
                let domainBytes = Array(host.utf8)
                guard !domainBytes.isEmpty, domainBytes.count <= 255 else { return }
                response.append(3)
                response.append(UInt8(domainBytes.count))
                response.append(contentsOf: domainBytes)
            }
            response.append(UInt8((port >> 8) & 0xFF))
            response.append(UInt8(port & 0xFF))
            response.append(responseData)
            self.sendToClient(response, sourceConnection: sourceConnection, queue: queue)
            self.receiveDirectReplies(relay, sourceConnection: sourceConnection, host: host, port: port, queue: queue)
        }
    }

    /// Ensures the upstream relay connection for the proxy route exists,
    /// performing the SOCKS5 ASSOCIATE handshake when needed.
    func ensureRelay(proxy: SOCKS5Proxy, queue: DispatchQueue, completion: @escaping (Bool) -> Void) {
        lock.lock()
        if let existing = relayUDP, existing.state == .ready {
            lock.unlock()
            completion(true)
            return
        }
        lock.unlock()

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(proxy.port)) else {
            completion(false)
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(proxy.host), port: nwPort)
        let proxyTCP = NWConnection(to: endpoint, using: .tcp)
        proxyTCP.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.performRelayAssociate(proxyTCP, proxy: proxy, queue: queue, completion: completion)
            case .failed(let error):
                SharedLogging.log("UDP relay: connection to proxy \(proxy.name) failed: \(error.localizedDescription)", category: .proxy, level: .error)
                completion(false)
            default:
                break
            }
        }
        proxyTCP.start(queue: queue)
    }

    private func performRelayAssociate(_ proxyTCP: NWConnection, proxy: SOCKS5Proxy, queue: DispatchQueue, completion: @escaping (Bool) -> Void) {
        let resolvedPassword = proxy.password ?? credentialStore.loadPassword(forProxyId: proxy.id.uuidString)
        var methods: [UInt8] = [0]
        if proxy.username != nil {
            methods.append(2)
        }
        let greeting = Data([5, UInt8(methods.count)] + methods)
        proxyTCP.send(content: greeting, completion: .contentProcessed { error in
            guard error == nil else {
                completion(false)
                return
            }
            self.handleGreetingReply(proxyTCP, proxy: proxy, resolvedPassword: resolvedPassword, queue: queue, completion: completion)
        })
    }

    private func handleGreetingReply(_ proxyTCP: NWConnection, proxy: SOCKS5Proxy, resolvedPassword: String?, queue: DispatchQueue, completion: @escaping (Bool) -> Void) {
        proxyTCP.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 2, error == nil else {
                completion(false)
                return
            }
            if data[1] == 2 {
                guard let username = proxy.username else {
                    completion(false)
                    return
                }
                let usernameBytes = Array(username.utf8)
                let passwordBytes = Array(resolvedPassword ?? "".utf8)
                guard usernameBytes.count <= 255, passwordBytes.count <= 255 else {
                    completion(false)
                    return
                }
                var auth = Data([1, UInt8(usernameBytes.count)])
                auth.append(contentsOf: usernameBytes)
                auth.append(UInt8(passwordBytes.count))
                auth.append(contentsOf: passwordBytes)
                proxyTCP.send(content: auth, completion: .contentProcessed { error in
                    guard error == nil else {
                        completion(false)
                        return
                    }
                    proxyTCP.receive(minimumIncompleteLength: 2, maximumLength: 2) { authData, _, _, error in
                        guard let authData = authData, authData.count == 2, error == nil, authData[1] == 0 else {
                            completion(false)
                            return
                        }
                        self.sendAssociate(proxyTCP, queue: queue, completion: completion)
                    }
                })
                return
            }
            guard data[1] == 0 else {
                completion(false)
                return
            }
            self.sendAssociate(proxyTCP, queue: queue, completion: completion)
        }
    }

    private func sendAssociate(_ proxyTCP: NWConnection, queue: DispatchQueue, completion: @escaping (Bool) -> Void) {
        let associate = Data([5, 3, 0, 1, 0, 0, 0, 0, 0, 0])
        proxyTCP.send(content: associate, completion: .contentProcessed { error in
            guard error == nil else {
                completion(false)
                return
            }
            proxyTCP.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, error in
                guard let data = data, data.count == 4, error == nil, data[1] == 0 else {
                    completion(false)
                    return
                }
                let atyp = data[3]
                var remaining = 0
                switch atyp {
                case 1: remaining = 6
                case 4: remaining = 18
                case 3:
                    proxyTCP.receive(minimumIncompleteLength: 1, maximumLength: 1) { lenData, _, _, error in
                        guard let lenData = lenData, lenData.count == 1, error == nil else {
                            completion(false)
                            return
                        }
                        let length = Int(lenData[0])
                        proxyTCP.receive(minimumIncompleteLength: length + 2, maximumLength: length + 2) { [weak self] addrData, _, _, error in
                            guard let self = self, let addrData = addrData, addrData.count == length + 2, error == nil else {
                                completion(false)
                                return
                            }
                            self.completeAssociate(proxyTCP, atyp: atyp, addrData: addrData, length: length, queue: queue, completion: completion)
                        }
                    }
                    return
                default:
                    completion(false)
                    return
                }
                proxyTCP.receive(minimumIncompleteLength: remaining, maximumLength: remaining) { [weak self] addrData, _, _, error in
                    guard let self = self, let addrData = addrData, addrData.count == remaining, error == nil else {
                        completion(false)
                        return
                    }
                    self.completeAssociate(proxyTCP, atyp: atyp, addrData: addrData, length: remaining, queue: queue, completion: completion)
                }
            }
        })
    }

    private func completeAssociate(_ proxyTCP: NWConnection, atyp: UInt8, addrData: Data, length: Int, queue: DispatchQueue, completion: @escaping (Bool) -> Void) {
        var relayHost = ""
        switch atyp {
        case 1:
            relayHost = "\(addrData[0]).\(addrData[1]).\(addrData[2]).\(addrData[3])"
        case 3:
            relayHost = String(data: addrData.subdata(in: 0..<length), encoding: .utf8) ?? ""
        case 4:
            relayHost = NetworkAddressMatcher.ipv6String(fromBytes: addrData.subdata(in: 0..<16))
        default:
            completion(false)
            return
        }
        let relayPort = (Int(addrData[length]) << 8) | Int(addrData[length + 1])
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(relayPort)) else {
            completion(false)
            return
        }
        let relayEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(relayHost), port: nwPort)
        let relayUDP = NWConnection(to: relayEndpoint, using: .udp)

        self.lock.lock()
        self.relayUDP = relayUDP
        self.relayTCP = proxyTCP
        self.lock.unlock()

        relayUDP.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                SharedLogging.log("UDP relay established via \(relayHost):\(relayPort).", category: .proxy)
                completion(true)
            } else if case .failed = state {
                completion(false)
            }
        }
        relayUDP.start(queue: queue)
        self.receiveRelayReplies(relayUDP, queue: queue)
    }

    private var relayTCP: NWConnection?

    func sendToRelay(_ packet: Data, sourceConnection: NWConnection, queue: DispatchQueue) {
        touchActivity()
        lock.lock()
        let relay = relayUDP
        lock.unlock()
        guard let relay = relay, relay.state == .ready else { return }
        relay.send(content: packet, completion: .contentProcessed { _ in })
    }

    private func receiveRelayReplies(_ relay: NWConnection, queue: DispatchQueue) {
        relay.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else { return }
            self.touchActivity()
            self.sendToClients(data)
            self.receiveRelayReplies(relay, queue: queue)
        }
    }

    private func sendToClient(_ data: Data, sourceConnection: NWConnection, queue: DispatchQueue) {
        if sourceConnection.state == .ready {
            sourceConnection.send(content: data, completion: .contentProcessed { _ in })
        } else {
            sendToClients(data)
        }
    }

    private func sendToClients(_ data: Data) {
        lock.lock()
        let clients = Array(clientConns.values)
        lock.unlock()
        for client in clients where client.state == .ready {
            client.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    func shutdown() {
        lock.lock()
        let relays = Array(directRelays.values)
        let relay = relayUDP
        let tcp = relayTCP
        directRelays.removeAll()
        relayUDP = nil
        relayTCP = nil
        idleTimer?.cancel()
        idleTimer = nil
        let clients = Array(clientConns.values)
        clientConns.removeAll()
        lock.unlock()

        for connection in relays {
            connection.cancel()
        }
        relay?.cancel()
        tcp?.cancel()
        for client in clients {
            client.cancel()
        }
        if clientConnection.state != .cancelled {
            clientConnection.cancel()
        }
    }
}