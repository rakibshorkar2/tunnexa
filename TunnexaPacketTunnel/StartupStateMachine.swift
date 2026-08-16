import Foundation

/// Coordinates the packet-tunnel startup continuation.
///
/// iOS reuses the same `NEPacketTunnelProvider` instance across tunnel
/// sessions, so startup state must be reset per `startTunnel` call — an
/// instance property initialized once would silently drop the completion
/// handler of every subsequent session (the tunnel then hangs in
/// `.connecting` until the system gives up).
///
/// Guarantees:
///  - `settle` invokes the completion handler at most once per session;
///  - `begin` always resets the previous session's state, so a new
///    `startTunnel` can never be blocked by a stale `.succeeded`/`.failed`;
///  - `cancel` (used by `stopTunnel`) retires any still-pending handler
///    without invoking it — the system is tearing the session down.
///
/// This type is compiled into the app target too so the tests can exercise
/// the lifecycle hermetically.
public final class StartupStateMachine {

    public enum State: Equatable {
        case inProgress
        case succeeded
        case failed
    }

    private let lock = NSLock()
    private var state: State = .inProgress
    private var pendingHandler: ((Error?) -> Void)?

    public init() {}

    public var currentState: State {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    public var isInProgress: Bool {
        lock.lock(); defer { lock.unlock() }
        return state == .inProgress
    }

    /// Starts (or restarts) a session. Any prior session's state and pending
    /// handler are discarded.
    public func begin(handler: @escaping (Error?) -> Void) {
        lock.lock()
        state = .inProgress
        pendingHandler = handler
        lock.unlock()
    }

    /// Settles the current session. Returns the completion handler to invoke
    /// (exactly once), or nil when the session already settled — in that case
    /// the handler must NOT be called.
    @discardableResult
    public func settle(_ error: Error?) -> ((Error?) -> Void)? {
        lock.lock()
        guard state == .inProgress, let handler = pendingHandler else {
            lock.unlock()
            return nil
        }
        state = error == nil ? .succeeded : .failed
        pendingHandler = nil
        lock.unlock()
        return handler
    }

    /// Retires any pending handler without invoking it (tunnel stop). The
    /// session is marked failed regardless of its previous state.
    public func cancel() {
        lock.lock()
        state = .failed
        pendingHandler = nil
        lock.unlock()
    }
}