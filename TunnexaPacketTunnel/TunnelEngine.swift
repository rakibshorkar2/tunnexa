import Foundation

#if canImport(Tun2SocksKit)
import Tun2SocksKit
#endif

/// Owns the blocking Tun2SocksKit engine loop and the TUN file descriptor.
///
/// Responsibilities:
///  - run the engine on a dedicated thread (the loop is injectable for tests);
///  - stop it cleanly with `Socks5Tunnel.quit()` (never a bare thread teardown);
///  - own the TUN descriptor: close it exactly once, and only after the engine
///    thread has exited (or as a `deinit` / stop-timeout safety net);
///  - expose running state and the engine exit code under a lock.
///
/// Ownership contract: the descriptor passed in `init` is transferred to the
/// engine. The caller must not close it (not even when the engine was never
/// started — `deinit` covers that), and the provider must stop using the
/// packet flow socket afterwards.
public final class TunnelEngine {

    public typealias EngineRun = (String) -> Int32

    private let configYAML: String
    private let tunFd: Int32
    private let run: EngineRun
    private let lock = NSLock()
    private let exitedSemaphore = DispatchSemaphore(value: 0)
    private var workerThread: Thread?
    private var fdClosed = false
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

    #if canImport(Tun2SocksKit)
    /// Default engine: runs the real Tun2SocksKit loop.
    public convenience init(configYAML: String, tunFd: Int32) {
        self.init(configYAML: configYAML, tunFd: tunFd) { config in
            Socks5Tunnel.run(withConfig: .string(content: config))
        }
    }
    #endif

    /// Designated initializer with an injectable engine loop (used by tests).
    public init(configYAML: String, tunFd: Int32, run: @escaping EngineRun) {
        self.configYAML = configYAML
        self.tunFd = tunFd
        self.run = run
    }

    deinit {
        // Safety net: never leak the TUN descriptor.
        closeFileDescriptor()
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
            self.closeFileDescriptor()
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
    /// The TUN descriptor is closed exactly once: here when the loop exits, or
    /// as a last resort after `timeout` if the loop refuses to terminate.
    public func stop(timeout: TimeInterval = 5.0) {
        lock.lock()
        guard let thread = workerThread else {
            lock.unlock()
            closeFileDescriptor()
            return
        }
        lock.unlock()

        SharedLogging.log("Requesting tunnel engine stop...", category: .tunnel)
        #if canImport(Tun2SocksKit)
        Socks5Tunnel.quit()
        #endif
        _ = exitedSemaphore.wait(timeout: .now() + timeout)

        if thread.isExecuting {
            SharedLogging.log("Tunnel engine did not exit in time; closing descriptor and signalling thread cancellation.", category: .tunnel, level: .warning)
            closeFileDescriptor()
            thread.cancel()
        }
        lock.lock()
        workerThread = nil
        lock.unlock()
        SharedLogging.log("Tunnel engine stopped.", category: .tunnel)
    }

    /// Closes the TUN descriptor unless it was already closed. Idempotent and
    /// safe to call from any thread (engine thread, stop(), deinit).
    private func closeFileDescriptor() {
        lock.lock()
        guard !fdClosed else {
            lock.unlock()
            return
        }
        fdClosed = true
        lock.unlock()
        close(tunFd)
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
    private var timer: Timer?
    private var lastUploadBytes: Int64 = 0
    private var lastDownloadBytes: Int64 = 0
    private let lock = NSLock()

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

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        timer.tolerance = 0.1
        self.timer = timer
        lock.unlock()
        RunLoop.main.add(timer, forMode: .common)
    }

    public func stop() {
        lock.lock()
        timer?.invalidate()
        timer = nil
        lock.unlock()
    }

    private func sample() {
        #if canImport(Tun2SocksKit)
        let stats = Socks5Tunnel.stats
        let upBytes = Int64(stats.up.bytes)
        let downBytes = Int64(stats.down.bytes)

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
        #endif
    }
}
