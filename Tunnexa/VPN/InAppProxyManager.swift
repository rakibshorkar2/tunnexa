import Foundation
import Combine

/// Runs the loopback SOCKS5 dispatcher inside the app process.
///
/// Used in runtimes where a system-wide VPN is impossible (LiveContainer
/// guests, the simulator). Guest applications configured to use SOCKS5
/// `127.0.0.1:10808` route through the selected proxies and rules.
///
/// Honesty contract: this is a local proxy, NOT a system VPN. No
/// `NETunnelProviderManager` is touched, no "connected" VPN state is faked,
/// and the UI never presents this mode as a system-wide VPN.
public final class InAppProxyManager: ObservableObject {

    public static let shared = InAppProxyManager()

    @Published public private(set) var isRunning = false
    @Published public private(set) var lastError: String?

    private let queue = DispatchQueue(label: "com.rakib.tunnexa.inappproxy")
    private var server: LocalProxyServer?

    private init() {}

    /// Starts the in-process dispatcher. Safe to call repeatedly; idempotent
    /// while already running. Reports failures through `lastError`.
    public func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.server != nil {
                self.publish { $0.isRunning = true }
                return
            }
            let settings = SharedSettings()
            guard settings.loadConfiguration() != nil else {
                self.publish { $0.lastError = "No proxy configuration found. Import a configuration first." }
                return
            }
            let server = LocalProxyServer(port: AppConfigConstants.localProxyPort, settings: settings)
            do {
                try server.start()
            } catch {
                self.publish { $0.lastError = "In-app proxy failed to start: \(error.localizedDescription)" }
                return
            }
            self.server = server
            self.publish {
                $0.isRunning = true
                $0.lastError = nil
            }
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.server?.stop()
            self.server = nil
            self.publish { $0.isRunning = false }
        }
    }

    private func publish(_ update: @escaping (InAppProxyManager) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            update(self)
        }
    }
}