import Foundation
import NetworkExtension
import Tun2SocksKit

public class PacketTunnelProvider: NEPacketTunnelProvider {

    private var localProxy: LocalProxyServer?
    private var engine: TunnelEngine?
    private var statsSampler: TunnelStatsSampler?

    public override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        SharedLogging.log("Starting Packet Tunnel Provider...", category: .vpn)

        let settings = SharedSettings()
        guard let config = settings.loadConfiguration() else {
            let error = NSError(domain: "Tunnexa.Provider", code: 100,
                                userInfo: [NSLocalizedDescriptionKey: "No proxy configuration found in shared defaults."])
            SharedLogging.log("startTunnel aborted: \(error.localizedDescription)", category: .vpn, level: .error)
            completionHandler(error)
            return
        }

        // Fail-closed: refuse to start a tunnel that cannot route anything.
        guard config.hasUsableSelection else {
            let error = NSError(domain: "Tunnexa.Provider", code: 101,
                                userInfo: [NSLocalizedDescriptionKey: "No proxies or groups configured. Import a configuration first."])
            SharedLogging.log("startTunnel aborted: \(error.localizedDescription)", category: .vpn, level: .error)
            completionHandler(error)
            return
        }
        if !SharedSettings.hasValidSelection(config: config, selectedProxy: settings.selectedProxyName, selectedGroup: settings.selectedGroupName) {
            let error = NSError(domain: "Tunnexa.Provider", code: 102,
                                userInfo: [NSLocalizedDescriptionKey: "The selected proxy is no longer available. Choose a proxy in the app and try again."])
            SharedLogging.log("startTunnel aborted: \(error.localizedDescription)", category: .vpn, level: .error)
            completionHandler(error)
            return
        }

        // 1. Tunnel network settings.
        let tunnelSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // MTU (validated).
        let mtu = settings.mtuOrDefault
        tunnelSettings.mtu = NSNumber(value: mtu)
        SharedLogging.log("Tunnel MTU: \(mtu)", category: .vpn)

        // IPv4: virtual address + default route.
        let ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]

        // Excluded routes: proxy IPs (prevent routing loops) + optional local network.
        var excludedRoutes: [NEIPv4Route] = []
        for proxy in config.proxies where NetworkAddressMatcher.isIPv4(proxy.host) {
            excludedRoutes.append(NEIPv4Route(destinationAddress: proxy.host, subnetMask: "255.255.255.255"))
        }
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
        let isIPv6Enabled = settings.ipv6Enabled
        if isIPv6Enabled {
            let ipv6Settings = NEIPv6Settings(addresses: ["fc00::1"], networkPrefixLengths: [NSNumber(value: 64)])
            ipv6Settings.includedRoutes = [NEIPv6Route.default()]
            var ipv6Excluded: [NEIPv6Route] = []
            for proxy in config.proxies where NetworkAddressMatcher.isIPv6(proxy.host) {
                ipv6Excluded.append(NEIPv6Route(destinationAddress: proxy.host, networkPrefixLength: 128))
            }
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
        let dnsSettings = NEDNSSettings(servers: ["198.18.0.2"])
        dnsSettings.matchDomains = [""]
        tunnelSettings.dnsSettings = dnsSettings

        setTunnelNetworkSettings(tunnelSettings) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                SharedLogging.log("Failed to set tunnel network settings: \(error.localizedDescription)", category: .vpn, level: .error)
                completionHandler(error)
                return
            }
            self.proceedAfterNetworkSettings(config: config, settings: settings, isIPv6Enabled: isIPv6Enabled, mtu: mtu, completionHandler: completionHandler)
        }
    }

    private func proceedAfterNetworkSettings(config: ProxyConfiguration, settings: SharedSettings, isIPv6Enabled: Bool, mtu: Int, completionHandler: @escaping (Error?) -> Void) {
        // 2. TUN file descriptor.
        // Primary: ioctl scan of the utun interfaces (no KVC). Fallback: the
        // documented-but-private `packetFlow.value(forKeyPath: "socket.fileDescriptor")`.
        guard let tunFd = TunnelFileDescriptor.tunnelFd() ?? TunnelFileDescriptor.kvcPacketFlowFd(of: packetFlow) else {
            let error = NSError(domain: "Tunnexa.Provider", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to extract TUN interface file descriptor."])
            SharedLogging.log("startTunnel aborted: \(error.localizedDescription)", category: .vpn, level: .error)
            completionHandler(error)
            return
        }
        SharedLogging.log("TUN file descriptor acquired: \(tunFd)", category: .tunnel)

        // 3. Local SOCKS5 dispatcher on 127.0.0.1:10808.
        let localPort: UInt16 = AppConfigConstants.localProxyPort
        let dispatcher = LocalProxyServer(port: localPort, settings: settings)
        dispatcher.hostResolver = { host, completion in
            ProxyEndpointResolver.shared.resolve(host: host, completion: completion)
        }
        do {
            try dispatcher.start()
        } catch {
            SharedLogging.log("Failed to start local SOCKS5 dispatcher: \(error.localizedDescription)", category: .vpn, level: .error)
            dispatcher.stop()
            completionHandler(error)
            return
        }
        localProxy = dispatcher

        // 4. Engine configuration.
        var configYAML = """
        tunnel:
          name: tun0
          mtu: \(mtu)
          fd: \(tunFd)
          ipv4: 198.18.0.1

        """
        if isIPv6Enabled {
            configYAML += "  ipv6: 'fc00::1'\n"
        }
        configYAML += """
        socks5:
          address: 127.0.0.1
          port: \(localPort)
          udp: udp
        mapdns:
          address: 198.18.0.2
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

        // 5. Engine + stats.
        let engine = TunnelEngine(configYAML: configYAML)
        engine.start()
        self.engine = engine

        let sampler = TunnelStatsSampler(settings: settings)
        sampler.start()
        statsSampler = sampler

        SharedLogging.log("Tunnel established (fd \(tunFd), MTU \(mtu)).", category: .vpn)
        completionHandler(nil)
    }

    public override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        SharedLogging.log("Stopping Packet Tunnel Provider... Reason: \(reason.rawValue)", category: .vpn)

        statsSampler?.stop()
        statsSampler = nil

        localProxy?.stop()
        localProxy = nil

        // Engine first, so no traffic flows while the dispatcher is down.
        engine?.stop()
        engine = nil

        completionHandler()
    }
}

// MARK: - TUN file descriptor acquisition

enum TunnelFileDescriptor {

    /// Scans utun0...utun255 via the Darwin control protocol and returns the
    /// first descriptor that binds successfully. This is the same mechanism
    /// the Tun2SocksKit engine uses for self-discovery, made explicit here so
    /// the provider does not depend on private KVC paths.
    static func tunnelFd() -> Int32? {
        for index in 0...255 {
            if let fd = openTunnelFd(utunIndex: index) {
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

    private static func openTunnelFd(utunIndex: Int) -> Int32? {
        let name = "utun\(utunIndex)"
        var interfaceName = [UInt8](repeating: 0, count: Int(IFNAMSIZ))
        name.withCString { source in
            _ = strlcpy(&interfaceName, source, interfaceName.count)
        }

        let fd = socket(AF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var controlInfo = ctl_info()
        "com.apple.net.utun_control".withCString { source in
            _ = strlcpy(&controlInfo.ctl_name, source, Int(CTL_MAX_NAME_LEN))
        }
        guard ioctl(fd, CTLIOCGINFO, &controlInfo) == 0 else { return nil }

        var controlAddress = sockaddr_ctl()
        controlAddress.sc_len = UInt8(MemoryLayout<sockaddr_ctl>.size)
        controlAddress.sc_family = AF_SYSTEM
        controlAddress.ss_sysaddr = AF_SYS_CONTROL
        controlAddress.sc_id = controlInfo.ctl_id
        controlAddress.sc_unit = UInt32(utunIndex)

        let connectResult = withUnsafePointer(to: &controlAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                connect(fd, address, socklen_t(MemoryLayout<sockaddr_ctl>.size))
            }
        }
        guard connectResult == 0 else { return nil }

        var boundName = [UInt8](repeating: 0, count: Int(IFNAMSIZ))
        var boundNameSize = socklen_t(boundName.count)
        guard getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, &boundName, &boundNameSize) == 0 else {
            return nil
        }
        return fd
    }
}