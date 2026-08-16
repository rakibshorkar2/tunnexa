import Foundation

/// Runtime environments Tunnexa can find itself in.
///
/// Ordering matters for honesty: a positive LiveContainer signature wins over
/// everything else; the simulator is detected at compile time; a bundle
/// identifier match is only trusted after both of those checks pass.
public enum VPNRuntimeEnvironment: String, CaseIterable, Codable {
    case standalone = "Standalone"
    case liveContainer = "LiveContainer Guest"
    case simulator = "Simulator"
    case unsupported = "Unsupported"
    case unknown = "Unknown"

    /// True only when a system-wide VPN is actually possible. `.unknown` is
    /// deliberately NOT supported — an ambiguous runtime must never be
    /// presented as able to run a packet tunnel.
    public var isSupportedForSystemVPN: Bool {
        switch self {
        case .standalone:
            return true
        case .liveContainer, .simulator, .unsupported, .unknown:
            return false
        }
    }
}

/// What the current runtime can actually do. The app derives its entire mode
/// of operation (system VPN vs in-app proxy vs nothing) from these three
/// flags — never from optimistic assumptions.
public struct EnvironmentCapabilities: Equatable {
    /// The process may manage and start an `NETunnelProviderManager` backed by
    /// the embedded `TunnexaPacketTunnel.appex`.
    public let canUsePacketTunnel: Bool
    /// The process may run the loopback SOCKS5 dispatcher in-process so guest
    /// applications (LiveContainer) or other local clients can use it.
    public let canUseInAppProxy: Bool
    /// The app-group store (`group.com.rakib.tunnexa`) is usable for
    /// cross-process configuration handoff.
    public let canUseSharedAppGroup: Bool

    public init(canUsePacketTunnel: Bool, canUseInAppProxy: Bool, canUseSharedAppGroup: Bool) {
        self.canUsePacketTunnel = canUsePacketTunnel
        self.canUseInAppProxy = canUseInAppProxy
        self.canUseSharedAppGroup = canUseSharedAppGroup
    }

    public static let none = EnvironmentCapabilities(canUsePacketTunnel: false, canUseInAppProxy: false, canUseSharedAppGroup: false)
}

public struct VPNEnvironmentDetector {

    /// Whether this build runs on the iOS simulator. Injectable so tests can
    /// exercise device-only branches while running on a simulator host.
    public static var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Detects the runtime environment.
    ///
    /// Injection points exist so tests can exercise every branch hermetically
    /// (including the device paths when the tests run on the simulator).
    public static func detectEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundlePath: String = Bundle.main.bundlePath,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        documentsPath: String? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path,
        isSimulator: Bool = isRunningOnSimulator
    ) -> VPNRuntimeEnvironment {

        // 1. Positive LiveContainer signatures (host sandbox paths/env vars).
        //    Checked first: a guest may masquerade under any bundle id.
        if environment["LC_APP_ID"] != nil ||
           environment["LIVE_CONTAINER"] != nil ||
           environment["LIVECONTAINER"] != nil ||
           environment["LC_BUNDLE_ID"] != nil {
            return .liveContainer
        }
        let lowerBundlePath = bundlePath.lowercased()
        if lowerBundlePath.contains("/livecontainer/") ||
           lowerBundlePath.contains("/data/app/") ||
           lowerBundlePath.contains("com.kdt.livecontainer") {
            return .liveContainer
        }
        if let docPath = documentsPath?.lowercased() {
            if docPath.contains("/livecontainer/") || docPath.contains("com.kdt.livecontainer") {
                return .liveContainer
            }
        }
        if let bundleID = bundleIdentifier?.lowercased(), bundleID.contains("livecontainer") {
            return .liveContainer
        }

        // 2. Simulator: compile-time fact. A packet tunnel provider cannot be
        //    validated on the simulator the way it can on a physical device.
        if isSimulator {
            return .simulator
        }

        // 3. Bundle identifier match. `com.rakib.tunnexa` only identifies a
        //    real standalone install after the checks above have passed.
        if bundleIdentifier?.lowercased() == "com.rakib.tunnexa" {
            return .standalone
        }

        // 4. Anything else is genuinely unknown — never assume support.
        return .unknown
    }

    /// The capabilities granted by `environment`.
    public static func capabilities(for environment: VPNRuntimeEnvironment) -> EnvironmentCapabilities {
        switch environment {
        case .standalone:
            return EnvironmentCapabilities(canUsePacketTunnel: true, canUseInAppProxy: false, canUseSharedAppGroup: true)
        case .liveContainer:
            // Guest sandbox: no NetworkExtension registration, no access to the
            // host app group — but the loopback dispatcher runs in-process.
            return EnvironmentCapabilities(canUsePacketTunnel: false, canUseInAppProxy: true, canUseSharedAppGroup: false)
        case .simulator:
            // The loopback dispatcher is fully exercisable on the simulator;
            // system VPN profiles are not.
            return EnvironmentCapabilities(canUsePacketTunnel: false, canUseInAppProxy: true, canUseSharedAppGroup: true)
        case .unsupported, .unknown:
            return .none
        }
    }

    /// Current capabilities of this process.
    public static func currentCapabilities() -> EnvironmentCapabilities {
        return capabilities(for: detectEnvironment())
    }

    /// Human-readable explanation of what the environment supports, for the
    /// Diagnostics screen.
    public static func capabilitySummary(for environment: VPNRuntimeEnvironment) -> [String] {
        let caps = capabilities(for: environment)
        var lines: [String] = []
        lines.append("System-wide VPN (Packet Tunnel): \(caps.canUsePacketTunnel ? "Available" : "Not available")")
        lines.append("In-app loopback SOCKS5 proxy: \(caps.canUseInAppProxy ? "Available" : "Not available")")
        lines.append("Shared app-group configuration: \(caps.canUseSharedAppGroup ? "Available" : "Not available")")
        return lines
    }
}