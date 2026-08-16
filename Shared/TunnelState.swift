import Foundation
import NetworkExtension

/// Single authoritative VPN state model.
///
/// The UI and view models must never infer VPN state from a raw boolean.
/// `NEVPNStatus` (from NetworkExtension) is authoritative; `TunnelState`
/// additionally folds in profile availability, profile validity and failure
/// information so the app can distinguish "disconnected" from "failed" and
/// "unavailable".
public enum TunnelState: String, Codable, Equatable {
    /// No manager/profile is available (e.g. LiveContainer, first launch).
    case unavailable
    /// A profile exists but is invalid (wrong bundle id, corrupt protocol).
    case invalid
    case disconnected
    /// Profile is being loaded / created.
    case preparing
    case connecting
    case connected
    case reasserting
    case disconnecting
    /// The tunnel failed (start-up error, unexpected disconnect, invalid selection).
    case failed
    /// The tunnel is up but the selected proxy is failing (engine reconnects
    /// or is in a degraded routing state).
    case degraded
    /// Reconnect attempts were exhausted after an unexpected proxy failure and
    /// fail-closed policy left traffic blocked rather than leaking directly.
    case proxyFailed
    /// A configuration/environment problem that cannot be recovered from
    /// without user action (missing config, invalid profile, unsupported
    /// runtime).
    case fatal

    public init(status: NEVPNStatus, profileAvailable: Bool = true, profileValid: Bool = true, hasFailure: Bool = false) {
        guard profileAvailable else {
            self = .unavailable
            return
        }
        guard profileValid else {
            self = .invalid
            return
        }
        switch status {
        case .invalid:
            self = .invalid
        case .disconnected:
            self = hasFailure ? .failed : .disconnected
        case .connecting:
            self = .connecting
        case .connected:
            self = .connected
        case .reasserting:
            self = .reasserting
        case .disconnecting:
            self = .disconnecting
        @unknown default:
            self = .unavailable
        }
    }

    public var isActive: Bool {
        switch self {
        case .connecting, .connected, .reasserting, .disconnecting, .degraded:
            return true
        default:
            return false
        }
    }

    public var isConnected: Bool {
        return self == .connected
    }

    public var isFailure: Bool {
        switch self {
        case .failed, .proxyFailed, .fatal:
            return true
        default:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .unavailable: return "Unavailable"
        case .invalid: return "Invalid Profile"
        case .disconnected: return "Disconnected"
        case .preparing: return "Preparing..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reasserting: return "Reconnecting..."
        case .disconnecting: return "Disconnecting..."
        case .failed: return "Failed"
        case .degraded: return "Degraded"
        case .proxyFailed: return "Proxy Failed (blocked)"
        case .fatal: return "Fatal"
        }
    }
}