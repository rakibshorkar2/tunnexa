import Foundation
import NetworkExtension
import Combine

/// Owns the Tunnexa VPN profile and its lifecycle.
///
/// Design guarantees:
///  - `state` is the single authoritative tunnel state (see `TunnelState`);
///  - `startVPN` only reports success once the tunnel actually reaches
///    `.connected` (or the 30 s wait times out) — never at `startVPNTunnel()`
///    invocation time;
///  - the profile is validated before starting (correct provider bundle id and
///    a usable proxy selection);
///  - auto-reconnect follows `AutoReconnectPolicy` (capped, backoff, cancelled
///    on user action);
///  - kill switch is implemented as routing-level fail-closed behaviour plus a
///    best-effort `NEOnDemandRuleConnect` — the latter only takes effect when
///    iOS is allowed to manage on-demand rules (documented limitation).
public class VPNManager: ObservableObject {

    public static let shared = VPNManager()
    public static let targetProviderBundleIdentifier = "com.rakib.tunnexa.PacketTunnel"

    @Published public private(set) var state: TunnelState = .unavailable
    @Published public private(set) var status: NEVPNStatus = .invalid
    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastError: VPNErrorDetails?
    @Published public private(set) var reconnectAttempt: Int = 0

    private var manager: NETunnelProviderManager?
    private var cancellables = Set<AnyCancellable>()
    private var pendingLoadCompletions: [(Result<NETunnelProviderManager, VPNErrorDetails>) -> Void] = []
    private var isInitializing = false

    private var connectWaiters: [(Result<Void, VPNErrorDetails>) -> Void] = []
    private var connectTimeoutWork: DispatchWorkItem?
    private var reconnectTimer: Timer?
    private var wasConnected = false
    /// Set when the user (or the app) explicitly stopped the tunnel. An
    /// unexpected `.disconnected` afterwards must not trigger auto-reconnect.
    private var userInitiatedStop = false

    private let connectTimeout: TimeInterval = 30.0

    private init() {
        SharedLogging.log("VPNManager initializing. Environment: \(VPNEnvironmentDetector.detectEnvironment().rawValue)", category: .vpn)
        observeStatus()
        loadProviderManager { [weak self] _ in
            self?.refreshState()
        }
    }

    // MARK: - Profile Discovery & Loading

    /// Loads (or creates) the Tunnexa profile. Every invocation calls back —
    /// concurrent callers are queued, never dropped.
    public func loadProviderManager(completion: @escaping (Result<NETunnelProviderManager, VPNErrorDetails>) -> Void) {
        let env = VPNEnvironmentDetector.detectEnvironment()

        guard env.isSupportedForSystemVPN else {
            let errorDetails = environmentUnsupportedError(env: env)
            self.lastError = errorDetails
            state = .unavailable
            completion(.failure(errorDetails))
            return
        }

        if let existing = manager {
            completion(.success(existing))
            return
        }

        pendingLoadCompletions.append(completion)
        guard !isInitializing else { return }
        isInitializing = true

        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            self.isInitializing = false

            let pending = self.pendingLoadCompletions
            self.pendingLoadCompletions.removeAll()

            if let error = error {
                let errorDetails = VPNErrorDetails(error: error, environment: env)
                self.lastError = errorDetails
                SharedLogging.log("Failed to load VPN profiles: \(errorDetails.message)", category: .vpn, level: .error)
                for completion in pending { completion(.failure(errorDetails)) }
                return
            }

            if let existingManager = self.findTunnexaManager(in: managers ?? []) {
                self.manager = existingManager
                SharedLogging.log("Reusing existing Tunnexa VPN profile.", category: .vpn)
                self.refreshState()
                for completion in pending { completion(.success(existingManager)) }
                return
            }

            self.createNewManagerProfile { result in
                for completion in pending { completion(result) }
            }
        }
    }

    private func findTunnexaManager(in managers: [NETunnelProviderManager]) -> NETunnelProviderManager? {
        return managers.first { manager in
            guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return false }
            return proto.providerBundleIdentifier == VPNManager.targetProviderBundleIdentifier
        }
    }

    private func createNewManagerProfile(completion: @escaping (Result<NETunnelProviderManager, VPNErrorDetails>) -> Void) {
        SharedLogging.log("Creating new Tunnexa VPN profile.", category: .vpn)

        let newManager = NETunnelProviderManager()
        let protocolConfig = NETunnelProviderProtocol()
        protocolConfig.providerBundleIdentifier = VPNManager.targetProviderBundleIdentifier
        protocolConfig.serverAddress = "127.0.0.1"
        newManager.protocolConfiguration = protocolConfig
        newManager.localizedDescription = "Tunnexa SOCKS5 VPN"
        newManager.isEnabled = true

        newManager.saveToPreferences { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                let errorDetails = VPNErrorDetails(error: error)
                self.lastError = errorDetails
                SharedLogging.log("Failed to save VPN profile: \(errorDetails.message)", category: .vpn, level: .error)
                completion(.failure(errorDetails))
                return
            }

            NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, reloadError in
                guard let self = self else { return }
                if let reloadError = reloadError {
                    let errorDetails = VPNErrorDetails(error: reloadError)
                    self.lastError = errorDetails
                    completion(.failure(errorDetails))
                    return
                }
                if let loaded = self.findTunnexaManager(in: managers ?? []) {
                    self.manager = loaded
                    self.refreshState()
                    SharedLogging.log("Tunnexa VPN profile created and loaded.", category: .vpn)
                    completion(.success(loaded))
                } else {
                    let errorDetails = VPNErrorDetails(
                        domain: "Tunnexa.Manager",
                        code: 404,
                        message: "Unable to locate saved Tunnexa profile after reload.",
                        environment: .standalone
                    )
                    self.lastError = errorDetails
                    completion(.failure(errorDetails))
                }
            }
        }
    }

    // MARK: - Status Observation

    private func observeStatus() {
        NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)
            .sink { [weak self] notification in
                guard let self = self,
                      let connection = notification.object as? NEVPNConnection else { return }
                self.handleStatusChange(connection.status)
            }
            .store(in: &cancellables)
    }

    private func handleStatusChange(_ newStatus: NEVPNStatus) {
        status = newStatus
        SharedLogging.log("VPN status: \(TunnelState(status: newStatus, profileAvailable: manager != nil).displayName)", category: .vpn)
        refreshState()

        switch newStatus {
        case .connected:
            wasConnected = true
            userInitiatedStop = false
            reconnectAttempt = 0
            cancelReconnectTimer()
            if state.isFailure {
                state = .disconnected
            }
            fulfillConnectWaiters(success: true)
        case .connecting, .reasserting:
            // Progress; no completion yet.
            break
        case .disconnected:
            let wasManual = userInitiatedStop
            userInitiatedStop = false
            if wasConnected, !wasManual {
                scheduleReconnectIfNeeded()
            }
            fulfillConnectWaiters(success: false)
        case .disconnecting, .invalid:
            fulfillConnectWaiters(success: false)
        @unknown default:
            break
        }
    }

    private func refreshState() {
        let env = VPNEnvironmentDetector.detectEnvironment()
        guard env.isSupportedForSystemVPN else {
            state = .unavailable
            return
        }
        guard let manager = manager else {
            state = .unavailable
            return
        }
        let profileValid = isProfileValid(manager)
        state = TunnelState(status: status, profileAvailable: true, profileValid: profileValid)
        isEnabled = manager.isEnabled
    }

    /// A profile is only usable when it targets our extension bundle id.
    private func isProfileValid(_ manager: NETunnelProviderManager) -> Bool {
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return false }
        return proto.providerBundleIdentifier == VPNManager.targetProviderBundleIdentifier
    }

    // MARK: - Connection Lifecycle

    public func startVPN(completion: @escaping (Result<Void, VPNErrorDetails>) -> Void) {
        let env = VPNEnvironmentDetector.detectEnvironment()
        userInitiatedStop = false
        guard env.isSupportedForSystemVPN else {
            let errorDetails = environmentUnsupportedError(env: env)
            lastError = errorDetails
            state = .unavailable
            completion(.failure(errorDetails))
            return
        }

        // Validate the selection BEFORE touching the profile.
        let settings = SharedSettings()
        guard let config = settings.loadConfiguration() else {
            failStart("No proxy configuration found. Import a configuration first.", code: 101, completion: completion)
            return
        }
        guard config.hasUsableSelection else {
            failStart("No proxies or groups configured. Import a configuration first.", code: 102, completion: completion)
            return
        }
        guard SharedSettings.hasValidSelection(config: config, selectedProxy: settings.selectedProxyName, selectedGroup: settings.selectedGroupName) else {
            failStart("No proxy selected. Choose a proxy before connecting.", code: 103, completion: completion)
            return
        }

        let ensureProfile: (@escaping (Result<NETunnelProviderManager, VPNErrorDetails>) -> Void) -> Void
        if let manager = manager {
            ensureProfile = { $0(.success(manager)) }
        } else {
            ensureProfile = loadProviderManager
        }

        ensureProfile { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let manager):
                self.startTunnel(with: manager, completion: completion)
            case .failure(let errorDetails):
                completion(.failure(errorDetails))
            }
        }
    }

    private func failStart(_ message: String, code: Int, completion: @escaping (Result<Void, VPNErrorDetails>) -> Void) {
        let errorDetails = VPNErrorDetails(domain: "Tunnexa.Validation", code: code, message: message, environment: .standalone)
        lastError = errorDetails
        SharedLogging.log("startVPN aborted: \(message)", category: .vpn, level: .error)
        completion(.failure(errorDetails))
    }

    /// Environment-specific refusal for runtimes that cannot host a system VPN.
    private func environmentUnsupportedError(env: VPNRuntimeEnvironment) -> VPNErrorDetails {
        let message: String
        let reason: String?
        switch env {
        case .liveContainer:
            message = "LiveContainer guest runtime detected."
            reason = "LiveContainer cannot register iOS NetworkExtension Packet Tunnel app extensions. Use the in-app proxy mode instead."
        case .simulator:
            message = "The iOS Simulator does not support Tunnexa's system-wide VPN."
            reason = "Packet tunnel providers cannot be validated on the simulator. Install Tunnexa on a physical iPhone to use the system VPN; the in-app proxy remains available for testing."
        case .unsupported, .unknown:
            message = "This runtime environment is not recognized as a supported Tunnexa installation."
            reason = "The app bundle, container path and environment could not be matched to a standalone install. Reinstall Tunnexa and try again."
        case .standalone:
            message = "System VPN is not available in this environment."
            reason = nil
        }
        return VPNErrorDetails(
            domain: "Tunnexa.Environment",
            code: 100,
            message: message,
            failureReason: reason,
            environment: env
        )
    }

    private func startTunnel(with manager: NETunnelProviderManager, completion: @escaping (Result<Void, VPNErrorDetails>) -> Void) {
        guard isProfileValid(manager) else {
            let errorDetails = VPNErrorDetails(
                domain: "Tunnexa.Validation",
                code: 104,
                message: "The VPN profile does not target the Tunnexa Packet Tunnel extension.",
                environment: .standalone
            )
            lastError = errorDetails
            state = .invalid
            completion(.failure(errorDetails))
            return
        }

        let applyKillSwitch = { [weak self] in
            guard let self = self else { return }
            self.applyKillSwitchIfNeeded(manager) {
                self.invokeStart(manager, completion: completion)
            }
        }

        if !manager.isEnabled {
            manager.isEnabled = true
            manager.saveToPreferences { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    let errorDetails = VPNErrorDetails(error: error)
                    self.lastError = errorDetails
                    SharedLogging.log("Failed to enable profile: \(errorDetails.message)", category: .vpn, level: .error)
                    completion(.failure(errorDetails))
                    return
                }
                applyKillSwitch()
            }
        } else {
            applyKillSwitch()
        }
    }

    private func invokeStart(_ manager: NETunnelProviderManager, completion: @escaping (Result<Void, VPNErrorDetails>) -> Void) {
        do {
            try manager.connection.startVPNTunnel()
        } catch {
            let errorDetails = VPNErrorDetails(error: error)
            lastError = errorDetails
            SharedLogging.log("startVPNTunnel() threw: \(errorDetails.message)", category: .vpn, level: .error)
            completion(.failure(errorDetails))
            return
        }

        SharedLogging.log("startVPNTunnel() invoked; waiting for .connected (max \(Int(connectTimeout))s).", category: .vpn)
        isBusy = true
        connectWaiters.append(completion)
        guard connectTimeoutWork == nil else { return }

        let timeoutWork = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let errorDetails = VPNErrorDetails(
                domain: "Tunnexa.Timeout",
                code: 10,
                message: "The tunnel did not reach the connected state within \(Int(self.connectTimeout)) seconds.",
                environment: .standalone
            )
            self.lastError = errorDetails
            self.isBusy = false
            self.fulfillConnectWaiters(success: false)
        }
        connectTimeoutWork = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + connectTimeout, execute: timeoutWork)
    }

    private func fulfillConnectWaiters(success: Bool) {
        let waiters = connectWaiters
        connectWaiters.removeAll()
        connectTimeoutWork?.cancel()
        connectTimeoutWork = nil
        isBusy = false
        for waiter in waiters {
            if success {
                waiter(.success(()))
            } else {
                let errorDetails = lastError ?? VPNErrorDetails(
                    domain: "Tunnexa.Connection",
                    code: 11,
                    message: "The tunnel disconnected before reaching the connected state.",
                    environment: .standalone
                )
                waiter(.failure(errorDetails))
            }
        }
    }

    public func stopVPN() {
        cancelReconnectTimer()
        reconnectAttempt = 0
        userInitiatedStop = true
        guard let manager = manager else { return }
        manager.connection.stopVPNTunnel()
        SharedLogging.log("stopVPNTunnel() requested (manual stop; auto-reconnect suppressed).", category: .vpn)
    }

    // MARK: - Auto-reconnect

    private func scheduleReconnectIfNeeded() {
        cancelReconnectTimer()
        guard SharedSettings().autoReconnect else {
            state = .proxyFailed
            return
        }
        guard AutoReconnectPolicy.mayRetry(afterAttempt: reconnectAttempt) else {
            SharedLogging.log("Auto-reconnect exhausted after \(reconnectAttempt) attempts; waiting for user action.", category: .vpn, level: .warning)
            // Fail-closed: the tunnel is down and we stop retrying. Never
            // silently fall back to direct networking.
            state = .proxyFailed
            return
        }
        state = .degraded
        reconnectAttempt += 1
        let attempt = reconnectAttempt
        let delay = AutoReconnectPolicy.jitteredDelay(forAttempt: attempt)
        SharedLogging.log("Scheduling auto-reconnect attempt \(attempt) in \(String(format: "%.1f", delay))s.", category: .vpn)

        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            SharedLogging.log("Auto-reconnect attempt \(attempt).", category: .vpn)
            self.startVPN { result in
                switch result {
                case .success:
                    break
                case .failure(let errorDetails):
                    SharedLogging.log("Auto-reconnect attempt \(attempt) failed: \(errorDetails.message)", category: .vpn, level: .error)
                }
            }
        }
        reconnectTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: - Kill switch (best-effort)

    private func applyKillSwitchIfNeeded(_ manager: NETunnelProviderManager, completion: @escaping () -> Void) {
        let enabled = SharedSettings().killSwitchEnabled
        let wantsOnDemand = enabled
        guard manager.isOnDemandEnabled != wantsOnDemand || (manager.onDemandRules?.isEmpty ?? true) != !wantsOnDemand else {
            completion()
            return
        }
        manager.isOnDemandEnabled = wantsOnDemand
        manager.onDemandRules = wantsOnDemand ? [NEOnDemandRuleConnect()] : nil
        manager.saveToPreferences { error in
            if let error = error {
                SharedLogging.log("Failed to apply on-demand (kill switch) rules: \(error.localizedDescription)", category: .vpn, level: .warning)
            } else {
                SharedLogging.log("On-demand (kill switch) rules \(wantsOnDemand ? "enabled" : "disabled").", category: .vpn)
            }
            completion()
        }
    }

    // MARK: - Auto-connect

    /// Called on app launch. Connects automatically when enabled in settings
    /// and the environment supports system VPNs.
    public func autoConnectIfNeeded() {
        guard SharedSettings().autoConnect else { return }
        let env = VPNEnvironmentDetector.detectEnvironment()
        guard env.isSupportedForSystemVPN else { return }
        guard !state.isActive, state == .disconnected || state == .unavailable else { return }

        loadProviderManager { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let manager):
                guard manager.connection.status == .disconnected, !self.state.isActive else { return }
                self.startVPN { _ in }
            case .failure:
                break
            }
        }
    }
}