import Foundation
import Tun2SocksKit

/// Owns the blocking Tun2SocksKit engine loop.
///
/// Responsibilities:
///  - run `Socks5Tunnel.run` on a dedicated thread;
///  - stop it cleanly with `Socks5Tunnel.quit()` (never a bare thread teardown);
///  - expose running state under a lock.
public final class TunnelEngine {

    private let configYAML: String
    private let lock = NSLock()
    private let exitedSemaphore = DispatchSemaphore(value: 0)
    private var workerThread: Thread?
    public private(set) var isRunning = false

    public init(configYAML: String) {
        self.configYAML = configYAML
    }

    public func start() {
        lock.lock()
        guard workerThread == nil else {
            lock.unlock()
            return
        }
        isRunning = true
        let config = configYAML
        let thread = Thread { [weak self] in
            let exitCode = Socks5Tunnel.run(withConfig: .string(content: config))
            SharedLogging.log("Socks5Tunnel exited with code \(exitCode).", category: .tunnel)
            self?.lock.lock()
            self?.isRunning = false
            self?.lock.unlock()
            self?.exitedSemaphore.signal()
        }
        thread.name = "Tunnexa.TunnelEngine"
        thread.qualityOfService = .userInteractive
        workerThread = thread
        lock.unlock()
        thread.start()
    }

    /// Requests the engine to stop and waits for the loop to exit.
    public func stop(timeout: TimeInterval = 5.0) {
        lock.lock()
        guard let thread = workerThread else {
            lock.unlock()
            return
        }
        lock.unlock()

        SharedLogging.log("Requesting Socks5Tunnel stop...", category: .tunnel)
        Socks5Tunnel.quit()
        _ = exitedSemaphore.wait(timeout: .now() + timeout)

        if thread.isExecuting {
            SharedLogging.log("Socks5Tunnel did not exit in time; signalling thread cancellation.", category: .tunnel, level: .warning)
            thread.cancel()
        }
        lock.lock()
        workerThread = nil
        lock.unlock()
        SharedLogging.log("TunnelEngine stopped.", category: .tunnel)
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
    }
}