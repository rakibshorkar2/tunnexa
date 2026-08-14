import Foundation

public enum VPNRuntimeEnvironment: String, CaseIterable, Codable {
    case standalone = "Standalone"
    case liveContainer = "LiveContainer Guest"
    case unknown = "Unknown"
    
    public var isSupportedForSystemVPN: Bool {
        switch self {
        case .standalone:
            return true
        case .liveContainer:
            return false
        case .unknown:
            return true
        }
    }
}

public struct VPNEnvironmentDetector {
    
    /// Conservatively detects the current runtime environment.
    /// Returns `.liveContainer` ONLY if positive signatures of LiveContainer's guest runner are discovered.
    public static func detectEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundlePath: String = Bundle.main.bundlePath,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        documentsPath: String? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
    ) -> VPNRuntimeEnvironment {
        
        // 1. Check LiveContainer specific environment variables
        if environment["LC_APP_ID"] != nil ||
           environment["LIVE_CONTAINER"] != nil ||
           environment["LIVECONTAINER"] != nil ||
           environment["LC_BUNDLE_ID"] != nil {
            return .liveContainer
        }
        
        // 2. Check main bundle path for LiveContainer directory signatures
        let lowerBundlePath = bundlePath.lowercased()
        if lowerBundlePath.contains("/livecontainer/") ||
           lowerBundlePath.contains("/data/app/") ||
           lowerBundlePath.contains("com.kdt.livecontainer") {
            return .liveContainer
        }
        
        // 3. Check document/container path for LiveContainer sandboxing signatures
        if let docPath = documentsPath?.lowercased() {
            if docPath.contains("/livecontainer/") || docPath.contains("com.kdt.livecontainer") {
                return .liveContainer
            }
        }
        
        // 4. Check main bundle identifier
        if let bundleID = bundleIdentifier?.lowercased() {
            if bundleID.contains("livecontainer") {
                return .liveContainer
            }
            if bundleID == "com.rakib.tunnexa" {
                return .standalone
            }
        }
        
        return .unknown
    }
}
