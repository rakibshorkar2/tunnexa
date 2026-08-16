import Foundation

/// Structured tunnel errors shared by the app and the Packet Tunnel extension.
///
/// Raw `errno` values and engine exit codes are preserved internally so
/// diagnostics can correlate them, but callers never have to interpret a bare
/// `-1` or `errno 22`.
public enum TunnelError: Error, Equatable, LocalizedError {

    /// The native engine could not be initialized (e.g. Tun2SocksKit failed to
    /// acquire the packet flow descriptor or initialize its runtime).
    case nativeInitializationFailed(code: Int32, detail: String)

    /// The stored configuration is missing, empty or has no usable selection.
    case invalidConfiguration

    /// The virtual tunnel interface / network settings could not be applied.
    case tunSetupFailed(detail: String)

    /// The selected proxy could not be reached or authenticated.
    case proxyUnavailable(detail: String)

    /// The engine loop exited unexpectedly (code != 0 or during startup).
    case engineExited(code: Int32)

    /// A system resource limit was hit (file descriptors, connections, memory).
    case resourceLimit(detail: String)

    /// The engine did not stop within the allowed window.
    case shutdownTimeout

    /// The local SOCKS5 dispatcher did not answer the startup probe.
    case probeFailed(detail: String)

    /// A mapped provider error with an opaque code.
    case unknown(code: Int, detail: String)

    /// Stable, diagnostic-friendly numeric code (used as NSError code).
    public var errorCode: Int {
        switch self {
        case .nativeInitializationFailed: return 1
        case .invalidConfiguration: return 100
        case .tunSetupFailed: return 3
        case .proxyUnavailable: return 6
        case .engineExited: return 4
        case .resourceLimit: return 7
        case .shutdownTimeout: return 8
        case .probeFailed: return 5
        case .unknown(let code, _): return code
        }
    }

    public var errorDescription: String? {
        switch self {
        case .nativeInitializationFailed(let code, let detail):
            return "Native engine initialization failed (code \(code)): \(detail)"
        case .invalidConfiguration:
            return "Invalid or missing proxy configuration."
        case .tunSetupFailed(let detail):
            return "Failed to set up the virtual tunnel interface: \(detail)"
        case .proxyUnavailable(let detail):
            return "Proxy unavailable: \(detail)"
        case .engineExited(let code):
            return "Tunnel engine exited unexpectedly (code \(code))."
        case .resourceLimit(let detail):
            return "Resource limit reached: \(detail)"
        case .shutdownTimeout:
            return "The tunnel engine did not stop within the allowed time."
        case .probeFailed(let detail):
            return "Local SOCKS5 dispatcher failed to answer: \(detail)"
        case .unknown(let code, let detail):
            return "Tunnel failure (code \(code)): \(detail)"
        }
    }

    /// Bridges to NSError for APIs that require it (e.g. the NetworkExtension
    /// completion handlers), preserving the native code in userInfo.
    public func asNSError(domain: String = "Tunnexa.Provider") -> NSError {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: errorDescription ?? "Tunnel failure"]
        switch self {
        case .nativeInitializationFailed(let code, _):
            userInfo["TunnexaNativeErrorCode"] = NSNumber(value: code)
        case .engineExited(let code):
            userInfo["TunnexaEngineExitCode"] = NSNumber(value: code)
        default:
            break
        }
        return NSError(domain: domain, code: errorCode, userInfo: userInfo)
    }

    /// Maps a provider error code + message into a structured error.
    public static func provider(code: Int, message: String) -> TunnelError {
        switch code {
        case 100, 101, 102:
            return .invalidConfiguration
        case 3:
            return .tunSetupFailed(detail: message)
        case 5:
            return .probeFailed(detail: message)
        case 6:
            return .proxyUnavailable(detail: message)
        case 7:
            return .resourceLimit(detail: message)
        default:
            return .unknown(code: code, detail: message)
        }
    }
}

/// Central errno → structured description helper.
///
/// `errno` must be captured immediately after the failing syscall — this
/// helper only formats the already-captured value.
public enum POSIXErrorDiagnostics {

    /// Human-readable description of an errno value (e.g. `EMFILE: Too many
    /// open files`), or nil when the errno is unknown.
    public static func describe(errno: Int32) -> String? {
        guard let code = POSIXErrorCode(rawValue: errno) else { return nil }
        switch code {
        case .EMFILE:
            return "EMFILE: Too many open files"
        case .ENFILE:
            return "ENFILE: File table overflow"
        case .EAGAIN:
            return "EAGAIN: Resource temporarily unavailable"
        case .EINVAL:
            return "EINVAL: Invalid argument"
        case .EADDRINUSE:
            return "EADDRINUSE: Address already in use"
        case .EADDRNOTAVAIL:
            return "EADDRNOTAVAIL: Address not available"
        case .ECONNREFUSED:
            return "ECONNREFUSED: Connection refused"
        case .ECONNRESET:
            return "ECONNRESET: Connection reset by peer"
        case .ENETUNREACH:
            return "ENETUNREACH: Network is unreachable"
        case .EHOSTUNREACH:
            return "EHOSTUNREACH: Host is unreachable"
        case .ETIMEDOUT:
            return "ETIMEDOUT: Connection timed out"
        case .EPERM:
            return "EPERM: Operation not permitted"
        case .ENOSPC:
            return "ENOSPC: No space left on device"
        case .ENOMEM:
            return "ENOMEM: Cannot allocate memory"
        default:
            return nil
        }
    }
}