import Foundation
import Network
import NetworkExtension
import Tun2SocksKit

public class PacketTunnelProvider: NEPacketTunnelProvider {

    private var localProxy: LocalProxyServer?
    private var engine: TunnelEngine?
    private var statsSampler: TunnelStatsSampler?

    /// Startup serialization: exactly one `completionHandler` call per tunnel
    /// session, even when several failure sources fire at once (engine exit +
    /// probe failure). The machine is reset on every `startTunnel` invocation
    /// because iOS reuses this provider instance across sessions.
    private let startup = StartupStateMachine()

    public override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        SharedLogging.log("Starting Packet Tunnel Provider...", category: .vpn)
        startup.begin(handler: completionHandler)

        let settings = SharedSettings()
        guard let config = settings.loadConfiguration() else {
            finishStartup(providerError(code: 100, message: "No proxy configuration found in shared defaults."))
            return
        }

        // Fail-closed: refuse to start a tunnel that cannot route anything.
        guard config.hasUsableSelection else {
            finishStartup(providerError(code: 101, message: "No proxies or groups configured. Import a configuration first."))
            return
        }
        if !SharedSettings.hasValidSelection(config: config, selectedProxy: settings.selectedProxyName, selectedGroup: settings.selectedGroupName) {
            finishStartup(providerError(code: 102, message: "The selected proxy is no longer available. Choose a proxy in the app and try again."))
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
                self.finishStartup(error)
                return
            }
            self.proceedAfterNetworkSettings(config: config, settings: settings, mtu: mtu, isIPv6Enabled: isIPv6Enabled)
        }
    }

    /// Everything after the network settings are applied. The startup only
    /// succeeds once every component is verified:
    ///  - the local dispatcher listener is actually `.ready`;
    ///  - the engine thread is running and does not exit during startup;
    ///  - the dispatcher answers a real SOCKS5 probe.
    ///
    /// The TUN descriptor is never touched by this code: `NEPacketTunnelFlow`
    /// owns it, and `Socks5Tunnel.run(withConfig:)` discovers it itself.
    /// Any failure tears everything down and reports the real error.
    private func proceedAfterNetworkSettings(config: ProxyConfiguration, settings: SharedSettings, mtu: Int, isIPv6Enabled: Bool) {

        // 2. Local SOCKS5 dispatcher on 127.0.0.1.
        let localPort: UInt16 = AppConfigConstants.localProxyPort
        let dispatcher = LocalProxyServer(port: localPort, settings: settings)
        dispatcher.hostResolver = { host, completion in
            ProxyEndpointResolver.shared.resolve(host: host, completion: completion)
        }
        do {
            try dispatcher.start()
        } catch {
            finishStartup(providerError(code: 3, message: "Failed to start local SOCKS5 dispatcher: \(error.localizedDescription)"))
            return
        }
        localProxy = dispatcher

        // 3. Engine.
        let configYAML = EngineConfigBuilder.build(mtu: mtu, isIPv6Enabled: isIPv6Enabled, localPort: localPort)
        let engine = TunnelEngine(configYAML: configYAML) { config in
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

        // 4. Probe the local dispatcher end-to-end (SOCKS5 greeting + CONNECT).
        guard probeLocalDispatcher(settings: settings, timeout: 5.0) else {
            finishStartup(providerError(code: 5, message: "Local SOCKS5 dispatcher did not answer the startup probe."))
            return
        }

        // 5. Statistics + success.
        let sampler = TunnelStatsSampler(settings: settings)
        sampler.statsProvider = { () -> (upBytes: Int64, downBytes: Int64)? in
            let stats = Socks5Tunnel.stats
            return (upBytes: Int64(stats.up.bytes), downBytes: Int64(stats.down.bytes))
        }
        sampler.start()
        statsSampler = sampler

        finishStartup(nil)
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
        guard startup.isInProgress else { return }
        finishStartup(providerError(code: 4, message: "Tunnel engine exited with code \(code) during startup."))
    }

    /// Single exit point for the startup continuation. Guarantees the
    /// completion handler runs exactly once; tears everything down on failure.
    private func finishStartup(_ error: Error?) {
        guard let handler = startup.settle(error) else { return }

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

        // Engine last; the loop is stopped via `Socks5Tunnel.quit()`.
        engine?.stop()
        engine = nil
    }

    public override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        SharedLogging.log("Stopping Packet Tunnel Provider... Reason: \(reason.rawValue)", category: .vpn)

        // Retire any still-pending startup (the system is tearing the session
        // down; the handler must not be invoked after stopTunnel).
        startup.cancel()

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