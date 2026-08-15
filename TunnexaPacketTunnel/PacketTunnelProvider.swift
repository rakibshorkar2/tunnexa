import Foundation
import Network
import NetworkExtension
import Tun2SocksKit

// The utun kernel-control constants live in <sys/kern_control.h> and
// <net/if_utun.h>, which the Swift Darwin module does not expose on iOS.
// Values below mirror the Darwin headers verbatim.
private let SYSPROTO_CONTROL: Int32 = 2
private let AF_SYS_CONTROL: UInt16 = 2
private let CTL_MAX_NAME_LEN = 96
private let CTLIOCGINFO: UInt = 0xc0644a03
private let UTUN_OPT_IFNAME: Int32 = 2

private struct ctl_info {
    var ctl_id: UInt32 = 0
    var ctl_name = [Int8](repeating: 0, count: CTL_MAX_NAME_LEN)
}

private struct sockaddr_ctl {
    var sc_len: UInt8 = 0
    var sc_family: UInt8 = 0
    var ss_sysaddr: UInt16 = 0
    var sc_id: UInt32 = 0
    var sc_unit: UInt32 = 0
    var sc_reserved = [UInt32](repeating: 0, count: 5)
}

public class PacketTunnelProvider: NEPacketTunnelProvider {

    private var localProxy: LocalProxyServer?
    private var engine: TunnelEngine?
    private var statsSampler: TunnelStatsSampler?

    // Startup serialization: exactly one `completionHandler` call, even when
    // several failure sources fire at once (engine exit + probe failure).
    private enum StartupState {
        case inProgress
        case succeeded
        case failed
    }
    private let stateLock = NSLock()
    private var startupState: StartupState = .inProgress
    private var pendingCompletionHandler: ((Error?) -> Void)?

    public override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        SharedLogging.log("Starting Packet Tunnel Provider...", category: .vpn)

        let settings = SharedSettings()
        guard let config = settings.loadConfiguration() else {
            completionHandler(providerError(code: 100, message: "No proxy configuration found in shared defaults."))
            return
        }

        // Fail-closed: refuse to start a tunnel that cannot route anything.
        guard config.hasUsableSelection else {
            completionHandler(providerError(code: 101, message: "No proxies or groups configured. Import a configuration first."))
            return
        }
        if !SharedSettings.hasValidSelection(config: config, selectedProxy: settings.selectedProxyName, selectedGroup: settings.selectedGroupName) {
            completionHandler(providerError(code: 102, message: "The selected proxy is no longer available. Choose a proxy in the app and try again."))
            return
        }

        // 1. Tunnel network settings.
        let tunnelSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let mtu = settings.mtuOrDefault
        tunnelSettings.mtu = NSNumber(value: mtu)
        SharedLogging.log("Tunnel MTU: \(mtu)", category: .vpn)

        // IPv4: virtual address + default route.
        let ipv4Settings = NEIPv4Settings(addresses: [AppConfigConstants.tunnelIPv4], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]

        // Excluded routes: proxy endpoints (prevent routing loops) + optional local network.
        let isIPv6Enabled = settings.ipv6Enabled
        let exclusions = resolvedProxyExclusions(config: config, isIPv6Enabled: isIPv6Enabled, budget: 2.0)
        var excludedRoutes = exclusions.ipv4.map { NEIPv4Route(destinationAddress: $0, subnetMask: "255.255.255.255") }
        SharedLogging.log("\(excludedRoutes.count) IPv4 proxy endpoint(s) excluded from the tunnel.", category: .vpn)

        let allowLocal = settings.allowLocalNetwork
        if allowLocal {
            excludedRoutes.append(NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"))
            excludedRoutes.append(NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"))
            excludedRoutes.append(NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"))
            SharedLogging.log("Local IPv4 networks excluded from the tunnel.", category: .vpn)
        }
        ipv4Settings.excludedRoutes = excludedRoutes
        tunnelSettings.ipv4Settings = ipv4Settings

        // IPv6 (optional).
        if isIPv6Enabled {
            let ipv6Settings = NEIPv6Settings(addresses: [AppConfigConstants.tunnelIPv6], networkPrefixLengths: [NSNumber(value: 64)])
            ipv6Settings.includedRoutes = [NEIPv6Route.default()]
            var ipv6Excluded = exclusions.ipv6.map { NEIPv6Route(destinationAddress: $0, networkPrefixLength: 128) }
            if allowLocal {
                ipv6Excluded.append(NEIPv6Route(destinationAddress: "fd00::", networkPrefixLength: 8))
                ipv6Excluded.append(NEIPv6Route(destinationAddress: "fe80::", networkPrefixLength: 10))
                ipv6Excluded.append(NEIPv6Route(destinationAddress: "::1", networkPrefixLength: 128))
            }
            ipv6Settings.excludedRoutes = ipv6Excluded
            tunnelSettings.ipv6Settings = ipv6Settings
            SharedLogging.log("IPv6 tunneling enabled with \(ipv6Excluded.count) excluded routes.", category: .vpn)
        }

        // DNS: redirected to the engine's built-in mapdns handler.
        let dnsSettings = NEDNSSettings(servers: [AppConfigConstants.dnsIPv4])
        dnsSettings.matchDomains = [""]
        tunnelSettings.dnsSettings = dnsSettings

        setTunnelNetworkSettings(tunnelSettings) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                SharedLogging.log("Failed to set tunnel network settings: \(error.localizedDescription)", category: .vpn, level: .error)
                completionHandler(error)
                return
            }
            self.proceedAfterNetworkSettings(config: config, settings: settings, mtu: mtu, isIPv6Enabled: isIPv6Enabled, completionHandler: completionHandler)
        }
    }

    /// Everything after the network settings are applied. The startup only
    /// succeeds once every component is verified:
    ///  - the TUN descriptor is acquired and handed to the engine;
    ///  - the local dispatcher listener is actually `.ready`;
    ///  - the engine thread is running and does not exit during startup;
    ///  - the dispatcher answers a real SOCKS5 probe.
    /// Any failure tears everything down and reports the real error.
    private func proceedAfterNetworkSettings(config: ProxyConfiguration, settings: SharedSettings, mtu: Int, isIPv6Enabled: Bool, completionHandler: @escaping (Error?) -> Void) {
        stateLock.lock()
        pendingCompletionHandler = completionHandler
        stateLock.unlock()

        // 2. TUN file descriptor.
        // Primary: ioctl scan of the existing utun interfaces (no KVC).
        // Fallback: the documented-but-private
        // `packetFlow.value(forKeyPath: "socket.fileDescriptor")`.
        guard let tunFd = TunnelFileDescriptor.tunnelFd() ?? TunnelFileDescriptor.kvcPacketFlowFd(of: packetFlow) else {
            finishStartup(providerError(code: 2, message: "Failed to extract TUN interface file descriptor."))
            return
        }
        SharedLogging.log("TUN file descriptor acquired: \(tunFd)", category: .tunnel)

        // 3. Local SOCKS5 dispatcher on 127.0.0.1.
        let localPort: UInt16 = AppConfigConstants.localProxyPort
        let dispatcher = LocalProxyServer(port: localPort, settings: settings)
        dispatcher.hostResolver = { host, completion in
            ProxyEndpointResolver.shared.resolve(host: host, completion: completion)
        }
        do {
            try dispatcher.start()
        } catch {
            // The descriptor was never handed to the engine: close it here.
            close(tunFd)
            finishStartup(providerError(code: 3, message: "Failed to start local SOCKS5 dispatcher: \(error.localizedDescription)"))
            return
        }
        localProxy = dispatcher

        // 4. Engine. Ownership of `tunFd` transfers to the engine.
        let configYAML = buildEngineConfigYAML(mtu: mtu, tunFd: tunFd, isIPv6Enabled: isIPv6Enabled, localPort: localPort)
        let engine = TunnelEngine(configYAML: configYAML, tunFd: tunFd) { config in
            Socks5Tunnel.run(withConfig: .string(content: config))
        }
        engine.onStopRequested = { Socks5Tunnel.quit() }
        engine.onExit = { [weak self] code in
            guard let self = self else { return }
            SharedLogging.log("Tunnel engine exited with code \(code).", category: .tunnel)
            self.failStartupIfStillInProgress(code: code)
        }
        engine.start()
        self.engine = engine

        guard waitForEngineAlive(engine, timeout: 2.0) else {
            finishStartup(providerError(code: 4, message: "Tunnel engine exited during startup."))
            return
        }

        // 5. Probe the local dispatcher end-to-end (SOCKS5 greeting + CONNECT).
        guard probeLocalDispatcher(settings: settings, timeout: 5.0) else {
            finishStartup(providerError(code: 5, message: "Local SOCKS5 dispatcher did not answer the startup probe."))
            return
        }

        // 6. Statistics + success.
        let sampler = TunnelStatsSampler(settings: settings)
        sampler.statsProvider = { () -> (upBytes: Int64, downBytes: Int64)? in
            let stats = Socks5Tunnel.stats
            return (upBytes: Int64(stats.up.bytes), downBytes: Int64(stats.down.bytes))
        }
        sampler.start()
        statsSampler = sampler

        finishStartup(nil)
    }

    private func buildEngineConfigYAML(mtu: Int, tunFd: Int32, isIPv6Enabled: Bool, localPort: UInt16) -> String {
        var configYAML = """
        tunnel:
          name: tun0
          mtu: \(mtu)
          fd: \(tunFd)
          ipv4: \(AppConfigConstants.tunnelIPv4)

        """
        if isIPv6Enabled {
            configYAML += "  ipv6: '\(AppConfigConstants.tunnelIPv6)'\n"
        }
        configYAML += """
        socks5:
          address: 127.0.0.1
          port: \(localPort)
          udp: udp
        mapdns:
          address: \(AppConfigConstants.dnsIPv4)
          port: 53
          network: 100.64.0.0
          netmask: 255.192.0.0
          cache-size: 10000
        misc:
          task-stack-size: 20480
          connect-timeout: 5000
          read-write-timeout: 60000
          log-file: stderr
          log-level: warn
          limit-nofile: 65535
        """
        return configYAML
    }

    /// Resolves hostname proxy endpoints once at startup so their IPs can be
    /// excluded from the tunnel routes (otherwise tunneled traffic to the
    /// proxy would loop). IP literals are used directly. Bounded by `budget`.
    private func resolvedProxyExclusions(config: ProxyConfiguration, isIPv6Enabled: Bool, budget: TimeInterval) -> (ipv4: [String], ipv6: [String]) {
        let deadline = Date().addingTimeInterval(budget)
        var ipv4: [String] = []
        var ipv6: [String] = []
        for proxy in config.proxies {
            let host = proxy.host.trimmingCharacters(in: .whitespacesAndNewlines)
            if NetworkAddressMatcher.isIPv4(host) {
                ipv4.append(host)
                continue
            }
            if NetworkAddressMatcher.isIPv6(host) {
                ipv6.append(host)
                continue
            }
            guard Date() < deadline else {
                SharedLogging.log("Skipping remaining hostname proxy exclusions (resolution budget exhausted).", category: .vpn, level: .warning)
                break
            }
            let addresses = ProxyEndpointResolver.shared.resolve(host: host, timeout: 1.5)
            for address in addresses {
                if NetworkAddressMatcher.isIPv4(address) {
                    ipv4.append(address)
                }
                if isIPv6Enabled, NetworkAddressMatcher.isIPv6(address) {
                    ipv6.append(address)
                }
            }
        }
        return (ipv4, ipv6)
    }

    /// Polls the engine briefly. False when the loop exited (or never started)
    /// within the window.
    private func waitForEngineAlive(_ engine: TunnelEngine, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if engine.exitCode != nil {
                return false
            }
            if engine.isRunning {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return engine.exitCode == nil && engine.isRunning
    }

    /// Fail the startup if it has not completed yet (engine exited early).
    private func failStartupIfStillInProgress(code: Int32) {
        stateLock.lock()
        let inProgress = startupState == .inProgress
        stateLock.unlock()
        guard inProgress else { return }
        finishStartup(providerError(code: 4, message: "Tunnel engine exited with code \(code) during startup."))
    }

    /// Single exit point for the startup continuation. Guarantees the
    /// completion handler runs exactly once; tears everything down on failure.
    private func finishStartup(_ error: Error?) {
        stateLock.lock()
        guard startupState == .inProgress, let handler = pendingCompletionHandler else {
            stateLock.unlock()
            return
        }
        startupState = error == nil ? .succeeded : .failed
        pendingCompletionHandler = nil
        stateLock.unlock()

        if let error = error {
            teardown()
            SharedLogging.log("Tunnel startup failed: \(error.localizedDescription)", category: .vpn, level: .error)
            handler(error)
        } else {
            SharedLogging.log("Tunnel established.", category: .vpn)
            handler(nil)
        }
    }

    private func teardown() {
        statsSampler?.stop()
        statsSampler = nil

        // Dispatcher first so no new traffic is accepted while the engine is
        // winding down.
        localProxy?.stop()
        localProxy = nil

        // Engine last: it owns the TUN descriptor and closes it exactly once
        // after its thread exits.
        engine?.stop()
        engine = nil
    }

    public override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        SharedLogging.log("Stopping Packet Tunnel Provider... Reason: \(reason.rawValue)", category: .vpn)

        stateLock.lock()
        startupState = .failed
        pendingCompletionHandler = nil
        stateLock.unlock()

        teardown()
        completionHandler()
    }

    private func providerError(code: Int, message: String) -> Error {
        NSError(domain: "Tunnexa.Provider", code: code,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - Startup probe

extension PacketTunnelProvider {

    /// Connects to the local SOCKS5 dispatcher and performs a real handshake:
    /// greeting, (auth), then CONNECT. Any well-formed SOCKS5 reply to the
    /// CONNECT proves the dispatcher is processing requests. The upstream
    /// connection may fail — the reply code is deliberately not checked.
    private func probeLocalDispatcher(settings: SharedSettings, timeout: TimeInterval) -> Bool {
        let queue = DispatchQueue(label: "com.rakib.tunnexa.provider.probe")
        guard let nwPort = NWEndpoint.Port(rawValue: AppConfigConstants.localProxyPort) else { return false }
        let connection = NWConnection(to: NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort), using: .tcp)
        let probeDone = DispatchSemaphore(value: 0)
        var probeResult = false

        func finish(_ success: Bool) {
            probeResult = success
            connection.cancel()
            probeDone.signal()
        }

        func probeConnect() {
            // Offer NO_AUTH and USERNAME/PASSWORD; the dispatcher picks one.
            connection.send(content: Data([5, 2, 0, 2]), completion: .contentProcessed { error in
                guard error == nil else {
                    finish(false)
                    return
                }
                readMethodSelection()
            })
        }

        func readMethodSelection() {
            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
                guard let data = data, data.count == 2, data[0] == 5, error == nil else {
                    finish(false)
                    return
                }
                switch data[1] {
                case 0:
                    probeConnectRequest()
                case 2:
                    probeAuthenticate()
                default:
                    finish(false)
                }
            }
        }

        func probeAuthenticate() {
            let username = settings.string(SettingsKey.localAuthUsername) ?? ""
            let password = settings.string(SettingsKey.localAuthPassword) ?? ""
            let usernameBytes = Array(username.utf8)
            let passwordBytes = Array(password.utf8)
            guard usernameBytes.count <= 255, passwordBytes.count <= 255 else {
                finish(false)
                return
            }
            var auth = Data([1, UInt8(usernameBytes.count)])
            auth.append(contentsOf: usernameBytes)
            auth.append(UInt8(passwordBytes.count))
            auth.append(contentsOf: passwordBytes)
            connection.send(content: auth, completion: .contentProcessed { error in
                guard error == nil else {
                    finish(false)
                    return
                }
                connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
                    guard let data = data, data.count == 2, data[0] == 1, data[1] == 0, error == nil else {
                        finish(false)
                        return
                    }
                    probeConnectRequest()
                }
            })
        }

        func probeConnectRequest() {
            // CONNECT 127.0.0.1:1. The reply code is irrelevant here.
            let request = Data([5, 1, 0, 1, 127, 0, 0, 1, 0, 1])
            connection.send(content: request, completion: .contentProcessed { error in
                guard error == nil else {
                    finish(false)
                    return
                }
                connection.receive(minimumIncompleteLength: 4, maximumLength: 10) { data, _, _, error in
                    guard let data = data, data.count >= 4, data[0] == 5, error == nil else {
                        finish(false)
                        return
                    }
                    finish(true)
                }
            })
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                probeConnect()
            case .failed:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)

        let timedOut = probeDone.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            connection.cancel()
            SharedLogging.log("Startup probe timed out after \(timeout)s.", category: .vpn, level: .error)
        }
        return probeResult
    }
}

// MARK: - TUN file descriptor acquisition

enum TunnelFileDescriptor {

    /// Returns an OWNED TUN file descriptor bound to an existing utun
    /// interface, or nil. The caller becomes the owner and must hand it to the
    /// engine (which closes it); it is never closed here.
    ///
    /// Strategy (avoids the `kCTLAll`/utun0 trap):
    ///  - enumerate the existing utun interfaces via `getifaddrs`;
    ///  - prefer the highest-numbered interface (the packet flow attaches to
    ///    the most recently created one);
    ///  - skip utun0 (reserved by the system — with `sc_unit == 0` the kernel
    ///    treats the request as `kCTLAll` and may create/steal an interface);
    ///  - verify the bound name after connect and reject mismatches.
    static func tunnelFd() -> Int32? {
        var indexes = existingUtunIndexes()
        indexes.removeAll { $0 == 0 }
        for index in indexes.sorted(by: >) {
            if let fd = openTunnelFd(utunIndex: index, expectedName: "utun\(index)") {
                return fd
            }
        }
        // No existing interface to attach to: request a specific free unit.
        // Never unit 0 (`kCTLAll`).
        for index in 1...255 {
            if let fd = openTunnelFd(utunIndex: index, expectedName: "utun\(index)") {
                return fd
            }
        }
        return nil
    }

    /// Documented fallback: reads the packet flow's socket descriptor through
    /// KVC. Works on current iOS versions but relies on a private key path.
    static func kvcPacketFlowFd(of packetFlow: NEPacketTunnelFlow) -> Int32? {
        guard let fd = packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32, fd > 0 else {
            return nil
        }
        return fd
    }

    private static func existingUtunIndexes() -> [Int] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let head = list else { return [] }
        defer { freeifaddrs(head) }
        var indexes: [Int] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let node = cursor {
            let name = String(cString: node.pointee.ifa_name)
            if name.hasPrefix("utun") {
                let digits = name.dropFirst(4)
                if !digits.isEmpty, let index = Int(digits) {
                    indexes.append(index)
                }
            }
            cursor = node.pointee.ifa_next
        }
        return indexes
    }

    /// Opens a control socket and attaches it to the requested utun unit.
    /// Returns the open descriptor on success (verified against
    /// `expectedName`); closes it on any failure. The descriptor is owned by
    /// the caller on success.
    private static func openTunnelFd(utunIndex: Int, expectedName: String) -> Int32? {
        let name = "utun\(utunIndex)"
        var interfaceName = [UInt8](repeating: 0, count: Int(IFNAMSIZ))
        name.withCString { source in
            _ = strlcpy(&interfaceName, source, interfaceName.count)
        }

        let fd = socket(AF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL)
        guard fd >= 0 else { return nil }

        var controlInfo = ctl_info()
        "com.apple.net.utun_control".withCString { source in
            _ = strlcpy(&controlInfo.ctl_name, source, Int(CTL_MAX_NAME_LEN))
        }
        guard ioctl(fd, CTLIOCGINFO, &controlInfo) == 0 else {
            close(fd)
            return nil
        }

        var controlAddress = sockaddr_ctl()
        controlAddress.sc_len = UInt8(MemoryLayout<sockaddr_ctl>.size)
        controlAddress.sc_family = UInt8(AF_SYSTEM)
        controlAddress.ss_sysaddr = AF_SYS_CONTROL
        controlAddress.sc_id = controlInfo.ctl_id
        controlAddress.sc_unit = UInt32(utunIndex)

        let connectResult = withUnsafePointer(to: &controlAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                connect(fd, address, socklen_t(MemoryLayout<sockaddr_ctl>.size))
            }
        }
        guard connectResult == 0 else {
            close(fd)
            return nil
        }

        var boundName = [UInt8](repeating: 0, count: Int(IFNAMSIZ))
        var boundNameSize = socklen_t(boundName.count)
        guard getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, &boundName, &boundNameSize) == 0 else {
            close(fd)
            return nil
        }
        let bound = String(bytes: boundName.prefix(Int(boundNameSize)), encoding: .utf8) ?? ""
        guard bound == expectedName else {
            SharedLogging.log("utun attach mismatch: requested \(expectedName), bound \(bound).", category: .tunnel, level: .warning)
            close(fd)
            return nil
        }
        return fd
    }
}
