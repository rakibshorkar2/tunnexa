import Foundation

/// Abstraction over the engine loop so tests can drive lifecycle behavior
/// (early exit, stop requests, restart) without a real tun2socks process.
public protocol TunnelBackend: AnyObject {
    var isRunning: Bool { get }
    var exitCode: Int32? { get }
    var onExit: ((Int32) -> Void)? { get set }
    var onStopRequested: (() -> Void)? { get set }
    func start()
    func stop(timeout: TimeInterval)
}

/// Owns the blocking engine loop.
///
/// Responsibilities:
///  - run the engine on a dedicated thread (the loop is injectable for tests);
///  - stop it cleanly (the stop-request is injectable — the provider wires
///    `Socks5Tunnel.quit()`, never a bare thread teardown);
///  - expose running state and the engine exit code under a lock.
///
/// This type is compiled into the app target too (so the tests can exercise
/// it), therefore it must not reference Tun2SocksKit directly — the provider
/// injects the real engine closures.
///
/// Descriptor contract: the TUN descriptor used by the engine belongs to
/// `NEPacketTunnelFlow`. Tun2SocksKit's `Socks5Tunnel.run(withConfig:)`
/// discovers that descriptor itself, and the C engine never closes an
/// externally supplied descriptor. This type (and the provider) therefore
/// never opens, receives or closes a descriptor — doing so would tear down
/// the packet flow while the tunnel is running.
public final class TunnelEngine: TunnelBackend {

    public typealias EngineRun = (String) -> Int32

    private let configYAML: String
    private let run: EngineRun
    private let lock = NSLock()
    private let exitedSemaphore = DispatchSemaphore(value: 0)
    private var workerThread: Thread?
    private var storedExitCode: Int32?
    private var storedIsRunning = false

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return storedIsRunning
    }

    /// Exit code of the engine loop, or nil while it is still running.
    public var exitCode: Int32? {
        lock.lock(); defer { lock.unlock() }
        return storedExitCode
    }

    /// Called exactly once when the engine loop exits, with its exit code.
    public var onExit: ((Int32) -> Void)?

    /// Called to request the engine loop to terminate (e.g. wired to
    /// `Socks5Tunnel.quit()` by the provider). Optional for tests.
    public var onStopRequested: (() -> Void)?

    /// Designated initializer with an injectable engine loop (used by tests
    /// and by the provider, which wires the real Tun2SocksKit loop here).
    public init(configYAML: String, run: @escaping EngineRun) {
        self.configYAML = configYAML
        self.run = run
    }

    public func start() {
        lock.lock()
        guard workerThread == nil else {
            lock.unlock()
            return
        }
        storedIsRunning = true
        let config = configYAML
        let run = self.run
        let thread = Thread { [weak self] in
            let exitCode = run(config)
            guard let self = self else { return }
            SharedLogging.log("Tunnel engine exited with code \(exitCode).", category: .tunnel)
            self.lock.lock()
            self.storedIsRunning = false
            self.storedExitCode = exitCode
            self.lock.unlock()
            self.exitedSemaphore.signal()
            self.onExit?(exitCode)
        }
        thread.name = "Tunnexa.TunnelEngine"
        thread.qualityOfService = .userInteractive
        workerThread = thread
        lock.unlock()
        thread.start()
    }

    /// Requests the engine to stop and waits for the loop to exit.
    ///
    /// If the loop refuses to terminate within `timeout`, the request is
    /// repeated on the engine thread via `Thread.cancel()` as a best-effort
    /// (blocking C calls cannot be interrupted; the extension is being torn
    /// down by the system at that point anyway).
    public func stop(timeout: TimeInterval = 5.0) {
        lock.lock()
        guard let thread = workerThread else {
            lock.unlock()
            return
        }
        lock.unlock()

        SharedLogging.log("Requesting tunnel engine stop...", category: .tunnel)
        onStopRequested?()
        _ = exitedSemaphore.wait(timeout: .now() + timeout)

        if thread.isExecuting {
            SharedLogging.log("Tunnel engine did not exit in time; signalling thread cancellation.", category: .tunnel, level: .warning)
            thread.cancel()
        }
        lock.lock()
        workerThread = nil
        lock.unlock()
        SharedLogging.log("Tunnel engine stopped.", category: .tunnel)
    }
}

/// Scriptable backend for tests: lifecycle is driven manually (no thread, no
/// real engine), so tests can exercise provider/manager reaction to an early
/// engine exit or a stop request deterministically.
public final class MockTunnelBackend: TunnelBackend {

    private let lock = NSLock()
    private var storedIsRunning = false
    private var storedExitCode: Int32?

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return storedIsRunning
    }

    public var exitCode: Int32? {
        lock.lock(); defer { lock.unlock() }
        return storedExitCode
    }

    public var onExit: ((Int32) -> Void)?
    public var onStopRequested: (() -> Void)?
    public private(set) var stopRequests = 0

    public init() {}

    public func start() {
        lock.lock()
        storedIsRunning = true
        storedExitCode = nil
        lock.unlock()
    }

    public func stop(timeout: TimeInterval = 5.0) {
        lock.lock()
        storedIsRunning = false
        lock.unlock()
        stopRequests += 1
        onStopRequested?()
    }

    /// Simulates the engine loop exiting on its own (e.g. a crash).
    public func simulateExit(code: Int32) {
        lock.lock()
        storedIsRunning = false
        storedExitCode = code
        lock.unlock()
        onExit?(code)
    }
}

/// Polls `Socks5Tunnel.stats` at 1 Hz and persists totals to the shared
/// defaults so the app can display live traffic figures.
///
/// Counters reflect traffic processed by the hev engine (the tunneled side).
/// Direct connections made by the local dispatcher bypass the engine and are
/// therefore not included — documented, accepted approximation.
public final class TunnelStatsSampler {

    private let settings: SharedSettings
    private var timer: DispatchSourceTimer?
    private var lastUploadBytes: Int64 = 0
    private var lastDownloadBytes: Int64 = 0
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.rakib.tunnexa.stats", qos: .utility)

    /// Injected engine counter source (up, down) in bytes. The provider wires
    /// `Socks5Tunnel.stats`; tests may leave it nil (then sampling is a no-op).
    public var statsProvider: (() -> (upBytes: Int64, downBytes: Int64)?)?

    public init(settings: SharedSettings) {
        self.settings = settings
    }

    public func start() {
        lock.lock()
        guard timer == nil else {
            lock.unlock()
            return
        }
        lastUploadBytes = settings.int64(SettingsKey.statUploadBytes)
        lastDownloadBytes = settings.int64(SettingsKey.statDownloadBytes)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.sample()
        }
        self.timer = timer
        lock.unlock()
        timer.resume()
    }

    public func stop() {
        lock.lock()
        timer?.cancel()
        timer = nil
        lock.unlock()
    }

    private func sample() {
        guard let stats = statsProvider?() else { return }
        let upBytes = stats.upBytes
        let downBytes = stats.downBytes

        lock.lock()
        let upDelta = upBytes - lastUploadBytes
        let downDelta = downBytes - lastDownloadBytes
        lastUploadBytes = upBytes
        lastDownloadBytes = downBytes
        lock.unlock()

        settings.set(upBytes, forKey: SettingsKey.statUploadBytes)
        settings.set(downBytes, forKey: SettingsKey.statDownloadBytes)
        settings.set(max(upDelta, 0), forKey: SettingsKey.statUploadSpeed)
        settings.set(max(downDelta, 0), forKey: SettingsKey.statDownloadSpeed)
    }
}