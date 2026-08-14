import Foundation

public struct VPNErrorDetails: Identifiable, Codable {
    public var id: String { "\(domain)_\(code)_\(timestamp.timeIntervalSince1970)" }
    public let timestamp: Date
    public let domain: String
    public let code: Int
    public let message: String
    public let failureReason: String?
    public let underlyingDomain: String?
    public let underlyingCode: Int?
    public let underlyingMessage: String?
    public let environment: VPNRuntimeEnvironment
    
    public init(
        error: Error,
        environment: VPNRuntimeEnvironment = VPNEnvironmentDetector.detectEnvironment()
    ) {
        self.timestamp = Date()
        self.environment = environment
        
        let nsError = error as NSError
        self.domain = nsError.domain
        self.code = nsError.code
        self.message = nsError.localizedDescription
        self.failureReason = nsError.localizedFailureReason
        
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            self.underlyingDomain = underlying.domain
            self.underlyingCode = underlying.code
            self.underlyingMessage = underlying.localizedDescription
        } else {
            self.underlyingDomain = nil
            self.underlyingCode = nil
            self.underlyingMessage = nil
        }
    }
    
    public init(
        domain: String,
        code: Int,
        message: String,
        failureReason: String? = nil,
        underlyingDomain: String? = nil,
        underlyingCode: Int? = nil,
        underlyingMessage: String? = nil,
        environment: VPNRuntimeEnvironment = VPNEnvironmentDetector.detectEnvironment()
    ) {
        self.timestamp = Date()
        self.domain = domain
        self.code = code
        self.message = message
        self.failureReason = failureReason
        self.underlyingDomain = underlyingDomain
        self.underlyingCode = underlyingCode
        self.underlyingMessage = underlyingMessage
        self.environment = environment
    }
    
    public var userFriendlyExplanation: String {
        if environment == .liveContainer {
            return """
            Unsupported Runtime Environment (LiveContainer)
            
            • Tunnexa requires an independently registered iOS NetworkExtension Packet Tunnel ('TunnexaPacketTunnel.appex') to route system-wide traffic.
            • LiveContainer runs guest applications inside a sandbox and cannot register app extensions with the iOS kernel.
            • This is an iOS platform and container constraint, not a SOCKS5 server or proxy configuration error.
            
            To use Tunnexa as a system-wide VPN:
            Install Tunnexa as a standalone iOS app using TrollStore, AltStore, or Sideloadly.
            """
        }
        
        // Handle common iOS NetworkExtension error domains and codes
        if domain == "NEVPNErrorDomain" || domain == "NETunnelProviderErrorDomain" {
            switch code {
            case 1: // ConfigurationInvalid
                return "VPN Configuration Invalid: The system rejected the tunnel settings. Verify that the Packet Tunnel extension is correctly embedded and signed."
            case 2: // ConfigurationDisabled
                return "VPN Configuration Disabled: The Tunnexa profile is currently disabled in iOS Settings -> VPN."
            case 3: // ConnectionFailed
                return "VPN Connection Failed: The Packet Tunnel extension failed to start. (\(underlyingMessage ?? message))"
            case 4: // ConfigurationStale
                return "VPN Configuration Stale: The VPN profile needs to be reloaded from iOS preferences."
            case 5: // ConfigurationReadWriteFailed / Permission denied
                return "VPN Permission Denied: iOS denied read/write access to system VPN preferences. Ensure your provisioning profile includes the 'com.apple.developer.networking.networkextension' entitlement."
            default:
                break
            }
        }
        
        var details = "\(message)"
        if let reason = failureReason {
            details += "\n\nReason: \(reason)"
        }
        if let underlying = underlyingMessage {
            details += "\n\nUnderlying Error: [\(underlyingDomain ?? "Unknown") \(underlyingCode ?? 0)] \(underlying)"
        }
        details += "\n\nError Reference: [\(domain) Code \(code)]"
        return details
    }
}
