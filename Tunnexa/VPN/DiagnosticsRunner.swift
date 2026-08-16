import Foundation

// MARK: - Diagnostics Bundle

/// A point-in-time snapshot of everything needed to diagnose tunnel problems,
/// with no secrets: credentials are never included; only the storage mode is
/// reported.
public struct DiagnosticsBundle {
    public let generatedAt: Date
    public let environment: VPNRuntimeEnvironment
    public let capabilities: EnvironmentCapabilities
    public let tunnelState: TunnelState
    public let proxyCount: Int
    public let groupCount: Int
    public let ruleCount: Int
    public let selectedProxy: String
    public let selectedGroup: String
    public let credentialStorageMode: CredentialStorageMode
    public let settings: [String: String]
    public let issues: [String]

    public var renderedText: String {
        var lines: [String] = []
        lines.append("Tunnexa Diagnostics")
        lines.append("Generated: \(generatedAt)")
        lines.append("Environment: \(environment.rawValue)")
        lines.append("System-wide VPN: \(capabilities.canUsePacketTunnel ? "Available" : "Not available")")
        lines.append("In-app proxy: \(capabilities.canUseInAppProxy ? "Available" : "Not available")")
        lines.append("Shared app group: \(capabilities.canUseSharedAppGroup ? "Available" : "Not available")")
        lines.append("Tunnel state: \(tunnelState.displayName)")
        lines.append("Proxies: \(proxyCount)  Groups: \(groupCount)  Rules: \(ruleCount)")
        lines.append("Selected proxy: \(selectedProxy.isEmpty ? "-" : selectedProxy)")
        lines.append("Selected group: \(selectedGroup.isEmpty ? "-" : selectedGroup)")
        lines.append("Credential storage: \(credentialStorageMode.rawValue)")
        lines.append("Settings:")
        for (key, value) in settings.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(key): \(value)")
        }
        if !issues.isEmpty {
            lines.append("Issues:")
            for issue in issues {
                lines.append("  - \(issue)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Collects the diagnostics snapshot. Pure and testable.
public enum DiagnosticsRunner {

    public static func collect(
        environment: VPNRuntimeEnvironment = VPNEnvironmentDetector.detectEnvironment(),
        tunnelState: TunnelState,
        settings: SharedSettings,
        credentialMode: CredentialStorageMode = KeychainHelper.shared.activeMode
    ) -> DiagnosticsBundle {
        let config = settings.loadConfiguration()
        let unresolved = config?.unresolvedReferences ?? []
        let capabilities = VPNEnvironmentDetector.capabilities(for: environment)

        var issues: [String] = []
        if environment == .liveContainer {
            issues.append("LiveContainer guest runtime: system-wide VPN is unavailable; use the in-app proxy mode.")
        }
        if environment == .simulator {
            issues.append("Simulator runtime: system-wide VPN is unavailable; use the in-app proxy mode for testing.")
        }
        if environment == .unknown || environment == .unsupported {
            issues.append("Unrecognized runtime: Tunnexa will not attempt to start a system VPN.")
        }
        if let config = config {
            if !config.hasUsableSelection {
                issues.append("Configuration contains no usable proxies or groups.")
            }
            if !unresolved.isEmpty {
                issues.append("Unresolved references: \(unresolved.joined(separator: ", ")).")
            }
        } else {
            issues.append("No configuration stored.")
        }
        if credentialMode == .insecureFallback {
            issues.append("Credential storage is using the insecure obfuscated fallback (development/unsigned build).")
        }
        if credentialMode == .unavailable {
            issues.append("Credential storage is unavailable; proxies requiring authentication will not work.")
        }
        if tunnelState == .invalid {
            issues.append("VPN profile is invalid (wrong extension bundle id).")
        }
        if capabilities.canUseInAppProxy, settings.inAppProxyEnabled {
            issues.append("In-app proxy mode is enabled.")
        }

        var settingsSummary: [String: String] = [:]
        settingsSummary["Auto-connect"] = settings.autoConnect ? "on" : "off"
        settingsSummary["Auto-reconnect"] = settings.autoReconnect ? "on" : "off"
        settingsSummary["Kill switch"] = settings.killSwitchEnabled ? "on" : "off"
        settingsSummary["Allow local network"] = settings.allowLocalNetwork ? "on" : "off"
        settingsSummary["IPv6"] = settings.ipv6Enabled ? "on" : "off"
        settingsSummary["MTU"] = settings.mtu.map { "\($0)" } ?? "default (\(MTULimit.defaultValue))"
        settingsSummary["Local auth"] = settings.bool(SettingsKey.localAuthEnabled) ? "on" : "off"
        settingsSummary["In-app proxy"] = settings.inAppProxyEnabled ? "on" : "off"
        settingsSummary["Configuration generation"] = "\(settings.configurationGeneration)"
        settingsSummary["Tunnel session"] = settings.sessionID(key: SettingsKey.tunnelSessionID) ?? "-"
        settingsSummary["Engine session"] = settings.sessionID(key: SettingsKey.engineSessionID) ?? "-"

        return DiagnosticsBundle(
            generatedAt: Date(),
            environment: environment,
            capabilities: capabilities,
            tunnelState: tunnelState,
            proxyCount: config?.proxies.count ?? 0,
            groupCount: config?.groups.count ?? 0,
            ruleCount: config?.rules.count ?? 0,
            selectedProxy: settings.selectedProxyName,
            selectedGroup: settings.selectedGroupName,
            credentialStorageMode: credentialMode,
            settings: settingsSummary,
            issues: issues
        )
    }

    /// Writes the diagnostics snapshot to a file and returns its URL.
    public static func exportToFile(
        environment: VPNRuntimeEnvironment = VPNEnvironmentDetector.detectEnvironment(),
        tunnelState: TunnelState,
        settings: SharedSettings,
        includeLogs: Bool = true
    ) -> URL? {
        let bundle = collect(environment: environment, tunnelState: tunnelState, settings: settings)
        var text = bundle.renderedText
        if includeLogs {
            text += "\n\n--- Log tail ---\n" + SharedLogging.readLogs()
        }
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let fileURL = directory.appendingPathComponent("tunnexa_diagnostics.txt")
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            SharedLogging.log("Failed to export diagnostics: \(error.localizedDescription)", category: .diagnostics, level: .error)
            return nil
        }
    }
}