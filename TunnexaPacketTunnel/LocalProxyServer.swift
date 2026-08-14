import Foundation
import Network

public class LocalProxyServer {
    private let port: UInt16
    private let sharedDefaults: UserDefaults
    private var listener: NWListener?
    private var activeConnections: Set<NWConnection> = []
    private let queue = DispatchQueue(label: "com.rakib.tunnexa.localproxy")
    
    var config: ProxyConfiguration?
    var selectedProxyName: String = ""
    var selectedGroupName: String = ""
    
    // Round-robin load balancer state
    private var loadBalanceIndices: [String: Int] = [:]
    private let stateQueue = DispatchQueue(label: "com.rakib.tunnexa.localproxy.state")
    
    public init(port: UInt16, sharedDefaults: UserDefaults) {
        self.port = port
        self.sharedDefaults = sharedDefaults
        loadConfig()
    }
    
    public func loadConfig() {
        if let configData = sharedDefaults.data(forKey: "proxy_config"),
           let parsed = try? JSONDecoder().decode(ProxyConfiguration.self, from: configData) {
            self.config = parsed
        }
        self.selectedProxyName = sharedDefaults.string(forKey: "selected_proxy") ?? ""
        self.selectedGroupName = sharedDefaults.string(forKey: "selected_group") ?? ""
    }
    
    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener
        
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                SharedLogging.log("Local SOCKS5 Dispatcher ready on port \(self.port)", category: .routing)
            case .failed(let error):
                SharedLogging.log("Local SOCKS5 Dispatcher failed: \(error)", category: .routing)
            default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener.start(queue: queue)
    }
    
    public func stop() {
        listener?.cancel()
        for connection in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()
        SharedLogging.log("Local SOCKS5 Dispatcher stopped.", category: .routing)
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        activeConnections.insert(connection)
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                self?.activeConnections.remove(connection)
            }
        }
        connection.start(queue: queue)
        readHandshake(connection)
    }
    
    private func readHandshake(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, context, isComplete, error in
            guard let self = self, let data = data, data.count == 2, error == nil else {
                connection.cancel()
                return
            }
            
            let version = data[0]
            let numMethods = Int(data[1])
            
            guard version == 5 else {
                connection.cancel()
                return
            }
            
            connection.receive(minimumIncompleteLength: numMethods, maximumLength: numMethods) { data, context, isComplete, error in
                guard let data = data, data.count == numMethods, error == nil else {
                    connection.cancel()
                    return
                }
                
                let response = Data([5, 0]) // Version 5, No Authentication
                connection.send(content: response, completion: .contentProcessed({ error in
                    if error != nil {
                        connection.cancel()
                    } else {
                        self.readRequest(connection)
                    }
                }))
            }
        }
    }
    
    private func readRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, context, isComplete, error in
            guard let self = self, let data = data, data.count == 4, error == nil else {
                connection.cancel()
                return
            }
            
            let version = data[0]
            let cmd = data[1] // 0x01 = CONNECT, 0x03 = UDP ASSOCIATE
            let atyp = data[3]
            
            guard version == 5 else {
                connection.cancel()
                return
            }
            
            if atyp == 1 { // IPv4
                connection.receive(minimumIncompleteLength: 6, maximumLength: 6) { data, context, isComplete, error in
                    guard let data = data, data.count == 6, error == nil else {
                        connection.cancel()
                        return
                    }
                    let ip = "\(data[0]).\(data[1]).\(data[2]).\(data[3])"
                    let port = (Int(data[4]) << 8) | Int(data[5])
                    self.processRoute(connection, cmd: cmd, host: ip, port: port, atyp: atyp)
                }
            } else if atyp == 3 { // Domain Name
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, context, isComplete, error in
                    guard let data = data, data.count == 1, error == nil else {
                        connection.cancel()
                        return
                    }
                    let len = Int(data[0])
                    connection.receive(minimumIncompleteLength: len + 2, maximumLength: len + 2) { data, context, isComplete, error in
                        guard let data = data, data.count == len + 2, error == nil else {
                            connection.cancel()
                            return
                        }
                        let domain = String(data: data.subdata(in: 0..<len), encoding: .utf8) ?? ""
                        let port = (Int(data[len]) << 8) | Int(data[len+1])
                        self.processRoute(connection, cmd: cmd, host: domain, port: port, atyp: atyp)
                    }
                }
            } else if atyp == 4 { // IPv6
                connection.receive(minimumIncompleteLength: 18, maximumLength: 18) { data, context, isComplete, error in
                    guard let data = data, data.count == 18, error == nil else {
                        connection.cancel()
                        return
                    }
                    let ip = self.parseIPv6(data.subdata(in: 0..<16))
                    let port = (Int(data[16]) << 8) | Int(data[17])
                    self.processRoute(connection, cmd: cmd, host: ip, port: port, atyp: atyp)
                }
            } else {
                connection.cancel()
            }
        }
    }
    
    private func parseIPv6(_ data: Data) -> String {
        var parts: [String] = []
        for i in stride(from: 0, to: 16, by: 2) {
            let val = (Int(data[i]) << 8) | Int(data[i+1])
            parts.append(String(format: "%x", val))
        }
        return parts.joined(separator: ":")
    }
    
    private func processRoute(_ connection: NWConnection, cmd: UInt8, host: String, port: Int, atyp: UInt8) {
        loadConfig()
        
        let matchedTarget = evaluateRules(host: host, port: port, cmd: cmd)
        SharedLogging.log("Route request: \(host):\(port) [\(cmd == 3 ? "UDP" : "TCP")] -> matched target: \(matchedTarget)", category: .routing)
        
        if cmd == 0x01 { // CONNECT
            if matchedTarget == "DIRECT" {
                connectDirect(connection, host: host, port: port)
            } else if let proxy = findProxyForTarget(matchedTarget) {
                connectViaProxy(connection, proxy: proxy, targetHost: host, targetPort: port)
            } else {
                SharedLogging.log("Failed to find proxy target '\(matchedTarget)', blocking traffic.", category: .routing)
                sendFailureResponse(connection)
            }
        } else if cmd == 0x03 { // UDP ASSOCIATE
            setupUDPRelay(connection, matchedTarget: matchedTarget, atyp: atyp)
        } else {
            sendFailureResponse(connection)
        }
    }
    
    func evaluateRules(host: String, port: Int, cmd: UInt8) -> String {
        guard let config = config else {
            return selectedProxyName.isEmpty ? "DIRECT" : selectedProxyName
        }
        
        let protocolStr = (cmd == 0x03) ? "UDP" : "TCP"
        
        for rule in config.rules {
            switch rule.type {
            case .domainSuffix:
                if let suffix = rule.payload, host.lowercased().hasSuffix(suffix.lowercased()) {
                    return rule.target
                }
            case .domainKeyword:
                if let keyword = rule.payload, host.lowercased().contains(keyword.lowercased()) {
                    return rule.target
                }
            case .domain:
                if let targetHost = rule.payload, host.lowercased() == targetHost.lowercased() {
                    return rule.target
                }
            case .network:
                if let net = rule.payload, net.uppercased() == protocolStr {
                    return rule.target
                }
            case .match:
                return rule.target
            }
        }
        
        if !selectedGroupName.isEmpty {
            return selectedGroupName
        }
        return selectedProxyName.isEmpty ? "DIRECT" : selectedProxyName
    }
    
    func findProxyForTarget(_ target: String) -> SOCKS5Proxy? {
        guard let config = config else { return nil }
        
        if let proxy = config.proxies.first(where: { $0.name == target }) {
            return proxy
        }
        
        if let group = config.groups.first(where: { $0.name == target }) {
            return resolveGroup(group)
        }
        
        return nil
    }
    
    func resolveGroup(_ group: ProxyGroup) -> SOCKS5Proxy? {
        switch group.type {
        case .select:
            let key = "selected_group_option_\(group.name)"
            let chosenOption = sharedDefaults.string(forKey: key) ?? group.proxies.first ?? ""
            if chosenOption == "DIRECT" {
                return nil
            }
            return findProxyForTarget(chosenOption)
            
        case .loadBalance:
            if group.strategy == "round-robin" {
                let list = group.proxies
                guard !list.isEmpty else { return nil }
                
                var chosenOption = ""
                stateQueue.sync {
                    let currentIndex = loadBalanceIndices[group.name] ?? 0
                    let nextIndex = (currentIndex + 1) % list.count
                    loadBalanceIndices[group.name] = nextIndex
                    chosenOption = list[currentIndex]
                }
                
                if chosenOption == "DIRECT" {
                    return nil
                }
                return findProxyForTarget(chosenOption)
            }
            
            if let first = group.proxies.first {
                if first == "DIRECT" { return nil }
                return findProxyForTarget(first)
            }
        }
        return nil
    }
    
    private func connectDirect(_ clientConnection: NWConnection, host: String, port: Int) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!)
        let destConnection = NWConnection(to: endpoint, using: .tcp)
        
        destConnection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.sendSuccessResponse(clientConnection, localIP: "127.0.0.1", localPort: self.port)
                self.bridgeConnections(clientConnection, destConnection)
            case .failed(let error):
                SharedLogging.log("Direct connection to \(host):\(port) failed: \(error)", category: .network)
                self.sendFailureResponse(clientConnection)
            default:
                break
            }
        }
        destConnection.start(queue: queue)
    }
    
    private func connectViaProxy(_ clientConnection: NWConnection, proxy: SOCKS5Proxy, targetHost: String, targetPort: Int) {
        let proxyEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(proxy.host), port: NWEndpoint.Port(rawValue: UInt16(proxy.port))!)
        let proxyConnection = NWConnection(to: proxyEndpoint, using: .tcp)
        
        proxyConnection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.performUpstreamHandshake(proxyConnection, proxy: proxy, targetHost: targetHost, targetPort: targetPort) { success in
                    if success {
                        self.sendSuccessResponse(clientConnection, localIP: "127.0.0.1", localPort: self.port)
                        self.bridgeConnections(clientConnection, proxyConnection)
                    } else {
                        SharedLogging.log("Upstream SOCKS5 handshake with \(proxy.name) failed.", category: .proxy)
                        self.sendFailureResponse(clientConnection)
                        proxyConnection.cancel()
                    }
                }
            case .failed(let error):
                SharedLogging.log("Connection to proxy \(proxy.name) (\(proxy.host):\(proxy.port)) failed: \(error)", category: .proxy)
                self.sendFailureResponse(clientConnection)
            default:
                break
            }
        }
        proxyConnection.start(queue: queue)
    }
    
    private func performUpstreamHandshake(_ connection: NWConnection, proxy: SOCKS5Proxy, targetHost: String, targetPort: Int, completion: @escaping (Bool) -> Void) {
        var methods = [UInt8]([0]) // No auth
        
        // Check keychain for password since config usually redacts it
        let resolvedPassword = proxy.password ?? KeychainHelper.shared.getPassword(forProxyId: proxy.id.uuidString)
        
        if proxy.username != nil && resolvedPassword != nil {
            methods.append(2) // Username/password auth
        }
        
        let handshake = Data([5, UInt8(methods.count)] + methods)
        connection.send(content: handshake, completion: .contentProcessed({ error in
            guard error == nil else {
                completion(false)
                return
            }
            
            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, context, isComplete, error in
                guard let self = self, let data = data, data.count == 2, error == nil else {
                    completion(false)
                    return
                }
                
                let version = data[0]
                let method = data[1]
                
                guard version == 5 else {
                    completion(false)
                    return
                }
                
                if method == 0 {
                    self.sendUpstreamRequest(connection, targetHost: targetHost, targetPort: targetPort, completion: completion)
                } else if method == 2, let username = proxy.username, let password = resolvedPassword {
                    self.performUpstreamAuth(connection, username: username, password: password) { authSuccess in
                        if authSuccess {
                            self.sendUpstreamRequest(connection, targetHost: targetHost, targetPort: targetPort, completion: completion)
                        } else {
                            completion(false)
                        }
                    }
                } else {
                    completion(false)
                }
            }
        }))
    }
    
    private func performUpstreamAuth(_ connection: NWConnection, username: String, password: String, completion: @escaping (Bool) -> Void) {
        let userBytes = Array(username.utf8)
        let passBytes = Array(password.utf8)
        
        guard userBytes.count <= 255, passBytes.count <= 255 else {
            completion(false)
            return
        }
        
        var authData = Data()
        authData.append(1) // Auth subnegotiation version
        authData.append(UInt8(userBytes.count))
        authData.append(contentsOf: userBytes)
        authData.append(UInt8(passBytes.count))
        authData.append(contentsOf: passBytes)
        
        connection.send(content: authData, completion: .contentProcessed({ error in
            guard error == nil else {
                completion(false)
                return
            }
            
            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, context, isComplete, error in
                guard let data = data, data.count == 2, error == nil else {
                    completion(false)
                    return
                }
                let status = data[1]
                completion(status == 0)
            }
        }))
    }
    
    private func sendUpstreamRequest(_ connection: NWConnection, targetHost: String, targetPort: Int, completion: @escaping (Bool) -> Void) {
        var req = Data([5, 1, 0])
        
        if let ipv4Data = IPv4StringToBytes(targetHost) {
            req.append(1) // ATYP: IPv4
            req.append(ipv4Data)
        } else if let ipv6Data = IPv6StringToBytes(targetHost) {
            req.append(4) // ATYP: IPv6
            req.append(ipv6Data)
        } else {
            req.append(3) // ATYP: Domain
            let domainBytes = Array(targetHost.utf8)
            guard domainBytes.count <= 255 else {
                completion(false)
                return
            }
            req.append(UInt8(domainBytes.count))
            req.append(contentsOf: domainBytes)
        }
        
        req.append(UInt8((targetPort >> 8) & 0xFF))
        req.append(UInt8(targetPort & 0xFF))
        
        connection.send(content: req, completion: .contentProcessed({ error in
            guard error == nil else {
                completion(false)
                return
            }
            
            connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, context, isComplete, error in
                guard let data = data, data.count == 4, data[1] == 0, error == nil else {
                    completion(false)
                    return
                }
                
                let atyp = data[3]
                var remainingLen = 0
                if atyp == 1 {
                    remainingLen = 6
                } else if atyp == 3 {
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { lenData, context, isComplete, error in
                        guard let lenData = lenData, lenData.count == 1, error == nil else {
                            completion(false)
                            return
                        }
                        let len = Int(lenData[0])
                        connection.receive(minimumIncompleteLength: len + 2, maximumLength: len + 2) { _, _, _, error in
                            completion(error == nil)
                        }
                    }
                    return
                } else if atyp == 4 {
                    remainingLen = 18
                } else {
                    completion(false)
                    return
                }
                
                connection.receive(minimumIncompleteLength: remainingLen, maximumLength: remainingLen) { _, _, _, error in
                    completion(error == nil)
                }
            }
        }))
    }
    
    private func sendSuccessResponse(_ connection: NWConnection, localIP: String, localPort: UInt16) {
        var response = Data([5, 0, 0, 1])
        response.append(Data([127, 0, 0, 1]))
        response.append(UInt8((localPort >> 8) & 0xFF))
        response.append(UInt8(localPort & 0xFF))
        connection.send(content: response, completion: .contentProcessed({ _ in }))
    }
    
    private func sendFailureResponse(_ connection: NWConnection) {
        let response = Data([5, 1, 0, 1, 0, 0, 0, 0, 0, 0])
        connection.send(content: response, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func bridgeConnections(_ conn1: NWConnection, _ conn2: NWConnection) {
        pipe(from: conn1, to: conn2)
        pipe(from: conn2, to: conn1)
    }
    
    private func pipe(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.recordTransfer(bytes: data.count, isUpload: (from === self?.activeConnections.first))
                
                to.send(content: data, completion: .contentProcessed({ [weak self] sendError in
                    if sendError == nil {
                        if isComplete {
                            to.send(content: nil, contentContext: .defaultStream, isComplete: true, completion: .idempotent)
                        } else {
                            self?.pipe(from: from, to: to)
                        }
                    } else {
                        from.cancel()
                        to.cancel()
                    }
                }))
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
    
    private var lastStatsUpdate: Date = Date()
    private var pendingUploadBytes = 0
    private var pendingDownloadBytes = 0
    
    private func recordTransfer(bytes: Int, isUpload: Bool) {
        if isUpload {
            pendingUploadBytes += bytes
        } else {
            pendingDownloadBytes += bytes
        }
        
        let now = Date()
        if now.timeIntervalSince(lastStatsUpdate) >= 1.0 {
            let up = pendingUploadBytes
            let down = pendingDownloadBytes
            pendingUploadBytes = 0
            pendingDownloadBytes = 0
            lastStatsUpdate = now
            
            queue.async {
                let keyUp = "stat_upload_bytes"
                let keyDown = "stat_download_bytes"
                
                let currentUp = self.sharedDefaults.integer(forKey: keyUp)
                let currentDown = self.sharedDefaults.integer(forKey: keyDown)
                
                self.sharedDefaults.set(currentUp + up, forKey: keyUp)
                self.sharedDefaults.set(currentDown + down, forKey: keyDown)
                
                self.sharedDefaults.set(up, forKey: "stat_upload_speed")
                self.sharedDefaults.set(down, forKey: "stat_download_speed")
            }
        }
    }
    
    private func IPv4StringToBytes(_ ip: String) -> Data? {
        let parts = ip.components(separatedBy: ".")
        guard parts.count == 4 else { return nil }
        var bytes = Data()
        for part in parts {
            guard let val = UInt8(part) else { return nil }
            bytes.append(val)
        }
        return bytes
    }
    
    private func IPv6StringToBytes(_ ip: String) -> Data? {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("::") {
            let parts = trimmed.components(separatedBy: "::")
            guard parts.count <= 2 else { return nil }
            
            let leftParts = parts[0].isEmpty ? [] : parts[0].components(separatedBy: ":")
            let rightParts = parts.count > 1 && !parts[1].isEmpty ? parts[1].components(separatedBy: ":") : []
            
            let leftCount = leftParts.count
            let rightCount = rightParts.count
            let zeroCount = 8 - (leftCount + rightCount)
            guard zeroCount >= 0 else { return nil }
            
            var allParts: [String] = []
            allParts.append(contentsOf: leftParts)
            allParts.append(contentsOf: Array(repeating: "0", count: zeroCount))
            allParts.append(contentsOf: rightParts)
            
            return ipv6PartsToBytes(allParts)
        } else {
            let parts = trimmed.components(separatedBy: ":")
            guard parts.count == 8 else { return nil }
            return ipv6PartsToBytes(parts)
        }
    }
    
    private func ipv6PartsToBytes(_ parts: [String]) -> Data? {
        var bytes = Data()
        for part in parts {
            guard let val = UInt16(part, radix: 16) else { return nil }
            bytes.append(UInt8((val >> 8) & 0xFF))
            bytes.append(UInt8(val & 0xFF))
        }
        return bytes
    }
    
    // MARK: - UDP Relay Implementation
    
    private func setupUDPRelay(_ clientConnection: NWConnection, matchedTarget: String, atyp: UInt8) {
        do {
            let parameters = NWParameters.udp
            parameters.requiredInterfaceType = .loopback
            let udpListener = try NWListener(using: parameters, on: .any)
            
            udpListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                if case .ready = state {
                    let assignedPort = udpListener.port!.rawValue
                    self.sendSuccessResponse(clientConnection, localIP: "127.0.0.1", localPort: assignedPort)
                }
            }
            
            udpListener.newConnectionHandler = { [weak self] udpConnection in
                self?.handleUDPClientConnection(udpConnection, matchedTarget: matchedTarget, atyp: atyp)
            }
            
            udpListener.start(queue: queue)
            
            clientConnection.stateUpdateHandler = { state in
                if case .cancelled = state {
                    udpListener.cancel()
                }
            }
        } catch {
            sendFailureResponse(clientConnection)
        }
    }
    
    private func handleUDPClientConnection(_ clientUDPConn: NWConnection, matchedTarget: String, atyp: UInt8) {
        clientUDPConn.start(queue: queue)
        
        clientUDPConn.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self = self, let data = data, data.count > 4, error == nil else { return }
            
            let frag = data[2]
            guard frag == 0 else { return }
            let atyp = data[3]
            
            var headerOffset = 4
            var host = ""
            var port = 0
            
            if atyp == 1 {
                guard data.count >= 10 else { return }
                host = "\(data[4]).\(data[5]).\(data[6]).\(data[7])"
                port = (Int(data[8]) << 8) | Int(data[9])
                headerOffset = 10
            } else if atyp == 3 {
                let len = Int(data[4])
                guard data.count >= 5 + len + 2 else { return }
                host = String(data: data.subdata(in: 5..<5+len), encoding: .utf8) ?? ""
                port = (Int(data[5+len]) << 8) | Int(data[5+len+1])
                headerOffset = 5 + len + 2
            } else if atyp == 4 {
                guard data.count >= 22 else { return }
                host = self.parseIPv6(data.subdata(in: 4..<20))
                port = (Int(data[20]) << 8) | Int(data[21])
                headerOffset = 22
            } else {
                return
            }
            
            let payload = data.subdata(in: headerOffset..<data.count)
            
            if matchedTarget == "DIRECT" {
                self.forwardUDPDirect(clientUDPConn, payload: payload, destHost: host, destPort: port, atyp: atyp)
            } else if let proxy = self.findProxyForTarget(matchedTarget) {
                self.forwardUDPViaProxy(clientUDPConn, payload: payload, destHost: host, destPort: port, proxy: proxy, atyp: atyp)
            }
        }
    }
    
    private func forwardUDPDirect(_ clientUDPConn: NWConnection, payload: Data, destHost: String, destPort: Int, atyp: UInt8) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(destHost), port: NWEndpoint.Port(rawValue: UInt16(destPort))!)
        let destUDPConn = NWConnection(to: endpoint, using: .udp)
        
        destUDPConn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                destUDPConn.send(content: payload, completion: .contentProcessed({ error in
                    if error == nil {
                        destUDPConn.receiveMessage { data, context, isComplete, error in
                            guard let data = data, error == nil else { return }
                            
                            var response = Data([0, 0, 0, atyp])
                            if atyp == 1 {
                                response.append(self.IPv4StringToBytes(destHost) ?? Data([0,0,0,0]))
                            } else if atyp == 3 {
                                let domainBytes = Array(destHost.utf8)
                                response.append(UInt8(domainBytes.count))
                                response.append(contentsOf: domainBytes)
                            } else if atyp == 4 {
                                response.append(self.IPv6StringToBytes(destHost) ?? Data(repeating: 0, count: 16))
                            }
                            response.append(UInt8((destPort >> 8) & 0xFF))
                            response.append(UInt8(destPort & 0xFF))
                            response.append(data)
                            
                            clientUDPConn.send(content: response, completion: .contentProcessed({ _ in }))
                            destUDPConn.cancel()
                        }
                    }
                }))
            }
        }
        destUDPConn.start(queue: queue)
    }
    
    private func forwardUDPViaProxy(_ clientUDPConn: NWConnection, payload: Data, destHost: String, destPort: Int, proxy: SOCKS5Proxy, atyp: UInt8) {
        let proxyTCP = NWConnection(to: NWEndpoint.hostPort(host: NWEndpoint.Host(proxy.host), port: NWEndpoint.Port(rawValue: UInt16(proxy.port))!), using: .tcp)
        
        proxyTCP.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                self.performUpstreamHandshake(proxyTCP, proxy: proxy, targetHost: "0.0.0.0", targetPort: 0) { success in
                    guard success else {
                        proxyTCP.cancel()
                        return
                    }
                    
                    let req = Data([5, 3, 0, 1, 0, 0, 0, 0, 0, 0]) // UDP ASSOCIATE
                    proxyTCP.send(content: req, completion: .contentProcessed({ error in
                        guard error == nil else {
                            proxyTCP.cancel()
                            return
                        }
                        
                        proxyTCP.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, context, isComplete, error in
                            guard let self = self, let data = data, data.count == 4, data[1] == 0, error == nil else {
                                proxyTCP.cancel()
                                return
                            }
                            
                            let repAtyp = data[3]
                            
                            func readAddressAndPort(len: Int) {
                                proxyTCP.receive(minimumIncompleteLength: len + 2, maximumLength: len + 2) { addrData, context, isComplete, error in
                                    guard let addrData = addrData, addrData.count == len + 2, error == nil else {
                                        proxyTCP.cancel()
                                        return
                                    }
                                    
                                    var relayHost = ""
                                    if repAtyp == 1 {
                                        relayHost = "\(addrData[0]).\(addrData[1]).\(addrData[2]).\(addrData[3])"
                                    } else if repAtyp == 3 {
                                        relayHost = String(data: addrData.subdata(in: 0..<len), encoding: .utf8) ?? ""
                                    }
                                    let relayPort = (Int(addrData[len]) << 8) | Int(addrData[len+1])
                                    
                                    self.sendUDPToRelay(clientUDPConn, payload: payload, destHost: destHost, destPort: destPort, relayHost: relayHost, relayPort: relayPort, atyp: atyp, proxyTCP: proxyTCP)
                                }
                            }
                            
                            if repAtyp == 1 {
                                readAddressAndPort(len: 4)
                            } else if repAtyp == 3 {
                                proxyTCP.receive(minimumIncompleteLength: 1, maximumLength: 1) { lenData, _, _, _ in
                                    if let lenData = lenData, lenData.count == 1 {
                                        readAddressAndPort(len: Int(lenData[0]))
                                    } else {
                                        proxyTCP.cancel()
                                    }
                                }
                            } else if repAtyp == 4 {
                                readAddressAndPort(len: 16)
                            }
                        }
                    }))
                }
            }
        }
        proxyTCP.start(queue: queue)
    }
    
    private func sendUDPToRelay(_ clientUDPConn: NWConnection, payload: Data, destHost: String, destPort: Int, relayHost: String, relayPort: Int, atyp: UInt8, proxyTCP: NWConnection) {
        let relayEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(relayHost), port: NWEndpoint.Port(rawValue: UInt16(relayPort))!)
        let relayUDPConn = NWConnection(to: relayEndpoint, using: .udp)
        
        relayUDPConn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                var packet = Data([0, 0, 0, atyp])
                if atyp == 1 {
                    packet.append(self.IPv4StringToBytes(destHost) ?? Data([0,0,0,0]))
                } else if atyp == 3 {
                    let domainBytes = Array(destHost.utf8)
                    packet.append(UInt8(domainBytes.count))
                    packet.append(contentsOf: domainBytes)
                } else if atyp == 4 {
                    packet.append(self.IPv6StringToBytes(destHost) ?? Data(repeating: 0, count: 16))
                }
                packet.append(UInt8((destPort >> 8) & 0xFF))
                packet.append(UInt8(destPort & 0xFF))
                packet.append(payload)
                
                relayUDPConn.send(content: packet, completion: .contentProcessed({ error in
                    if error == nil {
                        relayUDPConn.receiveMessage { data, context, isComplete, error in
                            guard let data = data, data.count > 4, error == nil else {
                                relayUDPConn.cancel()
                                proxyTCP.cancel()
                                return
                            }
                            
                            clientUDPConn.send(content: data, completion: .contentProcessed({ _ in }))
                            relayUDPConn.cancel()
                            proxyTCP.cancel()
                        }
                    } else {
                        relayUDPConn.cancel()
                        proxyTCP.cancel()
                    }
                }))
            }
        }
        relayUDPConn.start(queue: queue)
    }
}
