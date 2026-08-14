import Foundation
import NetworkExtension
import Combine

public class VPNManager: ObservableObject {
    public static let shared = VPNManager()
    
    @Published public var status: NEVPNStatus = .disconnected
    @Published public var isEnabled: Bool = false
    
    private var manager: NETunnelProviderManager?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadProviderManager { [weak self] _ in
            self?.observeStatus()
        }
    }
    
    public func loadProviderManager(completion: @escaping (Error?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            if let error = error {
                SharedLogging.log("Failed to load VPN profiles: \(error.localizedDescription)", category: .vpn)
                completion(error)
                return
            }
            
            if let managers = managers, let existingManager = managers.first {
                self.manager = existingManager
                self.status = existingManager.connection.status
                self.isEnabled = existingManager.isEnabled
                SharedLogging.log("Loaded existing VPN manager profile.", category: .vpn)
                completion(nil)
            } else {
                // Create a new manager
                let newManager = NETunnelProviderManager()
                let protocolConfig = NETunnelProviderProtocol()
                
                protocolConfig.providerBundleIdentifier = "com.rakib.tunnexa.PacketTunnel"
                protocolConfig.serverAddress = "TunnexaLocalTunnel" // Required dummy address
                
                // Configure local-network inclusion and kill switch options in protocol settings
                protocolConfig.username = "TunnexaUser"
                
                newManager.protocolConfiguration = protocolConfig
                newManager.localizedDescription = "Tunnexa SOCKS5 VPN"
                newManager.isEnabled = true
                
                newManager.saveToPreferences { error in
                    if let error = error {
                        SharedLogging.log("Failed to save new VPN manager profile: \(error.localizedDescription)", category: .vpn)
                        completion(error)
                        return
                    }
                    // Load again to fetch the finalized profile from preferences
                    NETunnelProviderManager.loadAllFromPreferences { managers, error in
                        if let managers = managers, let loadedManager = managers.first {
                            self.manager = loadedManager
                            self.status = loadedManager.connection.status
                            self.isEnabled = loadedManager.isEnabled
                            SharedLogging.log("Successfully created and loaded VPN manager profile.", category: .vpn)
                            completion(nil)
                        } else {
                            completion(error ?? NSError(domain: "Tunnexa", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to load saved VPN profile"]))
                        }
                    }
                }
            }
        }
    }
    
    private func observeStatus() {
        NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)
            .sink { [weak self] notification in
                guard let self = self,
                      let connection = notification.object as? NEVPNConnection else { return }
                self.status = connection.status
                SharedLogging.log("VPN connection status changed to: \(self.statusDescription(connection.status))", category: .vpn)
            }
            .store(in: &cancellables)
    }
    
    public func startVPN() throws {
        guard let manager = manager else {
            throw NSError(domain: "Tunnexa", code: 5, userInfo: [NSLocalizedDescriptionKey: "VPN Manager is not initialized"])
        }
        
        // Ensure manager is enabled
        if !manager.isEnabled {
            manager.isEnabled = true
            manager.saveToPreferences { error in
                if let error = error {
                    SharedLogging.log("Failed to enable VPN manager profile: \(error.localizedDescription)", category: .vpn)
                } else {
                    try? manager.connection.startVPNTunnel()
                }
            }
        } else {
            try manager.connection.startVPNTunnel()
        }
        SharedLogging.log("Initiated VPN tunnel connection.", category: .vpn)
    }
    
    public func stopVPN() {
        guard let manager = manager else { return }
        manager.connection.stopVPNTunnel()
        SharedLogging.log("Initiated VPN tunnel disconnection.", category: .vpn)
    }
    
    private func statusDescription(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid: return "Invalid"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reasserting: return "Reasserting"
        case .disconnecting: return "Disconnecting"
        @unknown default: return "Unknown"
        }
    }
}
