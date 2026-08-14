import Foundation
import NetworkExtension
import Tun2SocksKit

public class PacketTunnelProvider: NEPacketTunnelProvider {
    private var localProxy: LocalProxyServer?
    private var tunnelThread: Thread?
    
    public override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        SharedLogging.log("Starting Packet Tunnel Provider...", category: .vpn)
        
        let sharedDefaults = UserDefaults(suiteName: "group.com.rakib.tunnexa") ?? UserDefaults.standard
        
        // 1. Configure Tunnel Network Settings
        // We use 127.0.0.1 as the remote address because the SOCKS5 proxy loopback/local adapter runs locally.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        // MTU
        let configuredMtu = sharedDefaults.integer(forKey: "setting_mtu")
        settings.mtu = NSNumber(value: configuredMtu != 0 ? configuredMtu : 9000)
        
        // IPv4 Settings
        // Assign a virtual IP address inside the 198.18.0.0/24 subnet
        let ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        
        // Route all device traffic through this virtual interface
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        
        // Excluded routes to prevent routing loops (the remote proxy IP itself must NOT be routed through the tunnel)
        var excludedRoutes: [NEIPv4Route] = []
        
        if let configData = sharedDefaults.data(forKey: "proxy_config"),
           let config = try? JSONDecoder().decode(ProxyConfiguration.self, from: configData) {
            for proxy in config.proxies {
                if isIPAddress(proxy.host) {
                    excludedRoutes.append(NEIPv4Route(destinationAddress: proxy.host, subnetMask: "255.255.255.255"))
                }
            }
        }
        
        // Handle "Allow Local Network" setting
        let allowLocal = sharedDefaults.bool(forKey: "setting_allow_local")
        if allowLocal {
            // Standard RFC 1918 Private IP Ranges
            excludedRoutes.append(NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"))
            excludedRoutes.append(NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"))
            excludedRoutes.append(NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"))
            SharedLogging.log("Local network routes excluded from the tunnel.", category: .vpn)
        } else {
            SharedLogging.log("Local network traffic will be captured by the tunnel.", category: .vpn)
        }
        
        ipv4Settings.excludedRoutes = excludedRoutes
        settings.ipv4Settings = ipv4Settings
        
        // IPv6 Settings
        let isIPv6Enabled = sharedDefaults.bool(forKey: "setting_ipv6")
        if isIPv6Enabled {
            let ipv6Settings = NEIPv6Settings(addresses: ["fc00::1"], networkPrefixLengths: [NSNumber(value: 64)])
            ipv6Settings.includedRoutes = [NEIPv6Route.default()]
            settings.ipv6Settings = ipv6Settings
            SharedLogging.log("IPv6 tunneling enabled.", category: .vpn)
        }
        
        // DNS Settings
        // We direct DNS queries to 198.18.0.2, which is captured by the mapdns engine of hev-socks5-tunnel
        let dnsSettings = NEDNSSettings(servers: ["198.18.0.2"])
        dnsSettings.matchDomains = [""] // Match all domains
        settings.dnsSettings = dnsSettings
        
        // Apply settings to the virtual interface
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                SharedLogging.log("Failed to set tunnel network settings: \(error.localizedDescription)", category: .vpn)
                completionHandler(error)
                return
            }
            
            // 2. Extract TUN file descriptor via Key-Value Coding
            guard let tunFd = self.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 else {
                let error = NSError(domain: "Tunnexa", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to extract TUN interface file descriptor"])
                SharedLogging.log("Error: \(error.localizedDescription)", category: .vpn)
                completionHandler(error)
                return
            }
            
            SharedLogging.log("Extracted TUN file descriptor: \(tunFd)", category: .tunnel)
            
            // 3. Start our local SOCKS5 Dispatcher on localhost:10808
            let localPort: UInt16 = 10808
            self.localProxy = LocalProxyServer(port: localPort, sharedDefaults: sharedDefaults)
            do {
                try self.localProxy?.start()
            } catch {
                SharedLogging.log("Failed to start local SOCKS5 proxy: \(error.localizedDescription)", category: .vpn)
                self.localProxy?.stop()
                self.localProxy = nil
                completionHandler(error)
                return
            }
            
            // 4. Generate the YAML configuration content expected by hev-socks5-tunnel core
            var configYml = """
            tunnel:
              name: tun0
              mtu: \(settings.mtu?.intValue ?? 9000)
              fd: \(tunFd)
              ipv4: 198.18.0.1
            """
            
            if isIPv6Enabled {
                configYml += "\n  ipv6: 'fc00::1'"
            }
            
            configYml += """
            
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
            
            // 5. Spawn background thread to run the blocking Tun2SocksKit engine
            self.tunnelThread = Thread {
                SharedLogging.log("Starting Socks5Tunnel background loop...", category: .tunnel)
                let exitCode = Socks5Tunnel.run(withConfig: .string(content: configYml))
                SharedLogging.log("Socks5Tunnel exited with code \(exitCode)", category: .tunnel)
            }
            self.tunnelThread?.name = "Tunnexa.TunnelThread"
            self.tunnelThread?.start()
            
            SharedLogging.log("Tunnel successfully established.", category: .vpn)
            completionHandler(nil)
        }
    }
    
    public override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        SharedLogging.log("Stopping Packet Tunnel Provider... Reason: \(reason.rawValue)", category: .vpn)
        
        localProxy?.stop()
        localProxy = nil
        tunnelThread = nil
        
        completionHandler()
    }
    
    private func isIPAddress(_ host: String) -> Bool {
        let parts = host.components(separatedBy: ".")
        if parts.count == 4 {
            return parts.allSatisfy { Int($0) != nil && Int($0)! >= 0 && Int($0)! <= 255 }
        }
        let ipv6Parts = host.components(separatedBy: ":")
        if ipv6Parts.count >= 2 && ipv6Parts.count <= 8 {
            return ipv6Parts.allSatisfy { $0.isEmpty || Int($0, radix: 16) != nil }
        }
        return false
    }
}
