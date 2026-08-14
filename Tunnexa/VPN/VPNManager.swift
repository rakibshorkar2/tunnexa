import Foundation
import NetworkExtension
import Combine

public class VPNManager: ObservableObject {
    public static let shared = VPNManager()
    public static let targetProviderBundleIdentifier = "com.rakib.tunnexa.PacketTunnel"
    
    @Published public var status: NEVPNStatus = .disconnected
    @Published public var isEnabled: Bool = false
    @Published public var lastError: VPNErrorDetails?
    
    private var manager: NETunnelProviderManager?
    private var cancellables = Set<AnyCancellable>()
    private var isInitializing = false
    
    private init() {
        SharedLogging.log("VPNManager initializing. Environment detected: \(VPNEnvironmentDetector.detectEnvironment().rawValue)", category: .vpn)
        loadProviderManager { [weak self] _ in
            self?.observeStatus()
        }
    }
    
    // MARK: - Profile Discovery & Loading
    
    public func loadProviderManager(completion: @escaping (Result<NETunnelProviderManager, VPNErrorDetails>) -> Void) {
        let env = VPNEnvironmentDetector.detectEnvironment()
        
        // Fast-fail if in LiveContainer to avoid spamming system logs
        if env == .liveContainer {
            let errorDetails = VPNErrorDetails(
                domain: "Tunnexa.Environment",
                code: 100,
                message: "LiveContainer guest runtime detected.",
                failureReason: "LiveContainer cannot register iOS NetworkExtension Packet Tunnel app extensions.",
                environment: .liveContainer
            )
            self.lastError = errorDetails
            SharedLogging.log("VPN initialization aborted: LiveContainer guest environment.", category: .vpn)
            completion(.failure(errorDetails))
            return
        }
        
        guard !isInitializing else { return }
        isInitializing = true
        
        SharedLogging.log("Querying iOS preferences for existing VPN profiles...", category: .vpn)
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            self.isInitializing = false
            
            if let error = error {
                let errorDetails = VPNErrorDetails(error: error, environment: env)
                self.lastError = errorDetails
                SharedLogging.log("Failed to load VPN profiles from preferences: [\(errorDetails.domain) Code \(errorDetails.code)] \(errorDetails.message)", category: .vpn)
                completion(.failure(errorDetails))
                return
            }
            
            // Search specifically for Tunnexa Packet Tunnel profile
            if let managers = managers, let existingManager = self.findTunnexaManager(in: managers) {
                self.manager = existingManager
                self.status = existingManager.connection.status
                self.isEnabled = existingManager.isEnabled
                SharedLogging.log("Reusing existing Tunnexa VPN profile ('\(existingManager.localizedDescription ?? "Tunnexa")'). Status: \(self.statusDescription(existingManager.connection.status))", category: .vpn)
                completion(.success(existingManager))
            } else {
                // No profile exists yet — create fresh configuration
                self.createNewManagerProfile(completion: completion)
            }
        }
    }
    
    private func findTunnexaManager(in managers: [NETunnelProviderManager]) -> NETunnelProviderManager? {
        return managers.first { manager in
            guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return false }
            return proto.providerBundleIdentifier == VPNManager.targetProviderBundleIdentifier
        }
    }
    
    private func createNewManagerProfile(completion: @escaping (Result<NETunnelProviderManager, VPNErrorDetails>) -> Void) {
        SharedLogging.log("Creating new NETunnelProviderManager with bundle ID: \(VPNManager.targetProviderBundleIdentifier)", category: .vpn)
        
        let newManager = NETunnelProviderManager()
        let protocolConfig = NETunnelProviderProtocol()
        
        protocolConfig.providerBundleIdentifier = VPNManager.targetProviderBundleIdentifier
        protocolConfig.serverAddress = "127.0.0.1" // Loopback tunnel address
        protocolConfig.username = "TunnexaUser"
        
        newManager.protocolConfiguration = protocolConfig
        newManager.localizedDescription = "Tunnexa SOCKS5 VPN"
        newManager.isEnabled = true
        
        newManager.saveToPreferences { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                let errorDetails = VPNErrorDetails(error: error)
                self.lastError = errorDetails
                SharedLogging.log("Failed to save new VPN profile to preferences: [\(errorDetails.domain) Code \(errorDetails.code)] \(errorDetails.message)", category: .vpn)
                completion(.failure(errorDetails))
                return
            }
            
            SharedLogging.log("Saved new profile to preferences. Reloading to obtain system handle...", category: .vpn)
            
            // Reload all profiles to get the system-persisted instance
            NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, reloadError in
                guard let self = self else { return }
                
                if let reloadError = reloadError {
                    let errorDetails = VPNErrorDetails(error: reloadError)
                    self.lastError = errorDetails
                    SharedLogging.log("Failed to reload preferences after saving: \(errorDetails.message)", category: .vpn)
                    completion(.failure(errorDetails))
                    return
                }
                
                if let managers = managers, let loaded = self.findTunnexaManager(in: managers) {
                    self.manager = loaded
                    self.status = loaded.connection.status
                    self.isEnabled = loaded.isEnabled
                    SharedLogging.log("Successfully created, saved, and loaded Tunnexa VPN profile.", category: .vpn)
                    completion(.success(loaded))
                } else {
                    let errorDetails = VPNErrorDetails(
                        domain: "Tunnexa.Manager",
                        code: 404,
                        message: "Unable to locate saved Tunnexa profile after reload.",
                        failureReason: "iOS preferences did not return the expected manager."
                    )
                    self.lastError = errorDetails
                    completion(.failure(errorDetails))
                }
            }
        }
    }
    
    // MARK: - Status Observation
    
    private func observeStatus() {
        NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)
            .sink { [weak self] notification in
                guard let self = self,
                      let connection = notification.object as? NEVPNConnection else { return }
                self.status = connection.status
                SharedLogging.log("VPN status notification: \(self.statusDescription(connection.status))", category: .vpn)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Connection Lifecycle
    
    public func startVPN(completion: @escaping (Result<Void, VPNErrorDetails>) -> Void) {
        let env = VPNEnvironmentDetector.detectEnvironment()
        
        if env == .liveContainer {
            let errorDetails = VPNErrorDetails(
                domain: "Tunnexa.Environment",
                code: 100,
                message: "LiveContainer guest runtime cannot run system-wide VPN tunnels.",
                environment: .liveContainer
            )
            self.lastError = errorDetails
            completion(.failure(errorDetails))
            return
        }
        
        if let manager = self.manager {
            self.startTunnel(with: manager, completion: completion)
        } else {
            SharedLogging.log("No cached manager profile. Initializing on demand before connection...", category: .vpn)
            self.loadProviderManager { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let loadedManager):
                    self.startTunnel(with: loadedManager, completion: completion)
                case .failure(let errorDetails):
                    completion(.failure(errorDetails))
                }
            }
        }
    }
    
    private func startTunnel(with manager: NETunnelProviderManager, completion: @escaping (Result<Void, VPNErrorDetails>) -> Void) {
        SharedLogging.log("Starting VPN tunnel with provider: \(manager.localizedDescription ?? "Tunnexa")", category: .vpn)
        
        if !manager.isEnabled {
            manager.isEnabled = true
            manager.saveToPreferences { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    let errorDetails = VPNErrorDetails(error: error)
                    self.lastError = errorDetails
                    SharedLogging.log("Failed to enable profile during start: \(errorDetails.message)", category: .vpn)
                    completion(.failure(errorDetails))
                    return
                }
                
                self.executeStartVPNTunnel(manager: manager, completion: completion)
            }
        } else {
            self.executeStartVPNTunnel(manager: manager, completion: completion)
        }
    }
    
    private func executeStartVPNTunnel(manager: NETunnelProviderManager, completion: @escaping (Result<Void, VPNErrorDetails>) -> Void) {
        do {
            try manager.connection.startVPNTunnel()
            self.lastError = nil
            SharedLogging.log("startVPNTunnel() invoked successfully.", category: .vpn)
            completion(.success(()))
        } catch {
            let errorDetails = VPNErrorDetails(error: error)
            self.lastError = errorDetails
            SharedLogging.log("startVPNTunnel() threw error: [\(errorDetails.domain) Code \(errorDetails.code)] \(errorDetails.message)", category: .vpn)
            completion(.failure(errorDetails))
        }
    }
    
    public func stopVPN() {
        guard let manager = manager else { return }
        manager.connection.stopVPNTunnel()
        SharedLogging.log("stopVPNTunnel() requested.", category: .vpn)
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
