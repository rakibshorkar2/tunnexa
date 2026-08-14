import Foundation
import SwiftUI

public enum ProxySortOrder: String, CaseIterable {
    case name = "Name"
    case latency = "Latency"
}

/// Central model for proxies, groups, rules, selection and health testing.
///
/// Configuration storage rules:
///  - writes go through `SharedSettings.saveConfiguration` (single atomic blob
///    with a bumped `revision` — never partial writes);
///  - passwords are never stored in the configuration; they live in the
///    credential store keyed by proxy UUID;
///  - proxy UUIDs are stable: re-importing a configuration that contains the
///    same name/host/port reuses the existing UUID so credentials and latency
///    history survive re-imports.
public class ProxyViewModel: ObservableObject {

    @Published public var proxies: [SOCKS5Proxy] = []
    @Published public var groups: [ProxyGroup] = []
    @Published public var rules: [Rule] = []

    @Published public var selectedProxyName: String = ""
    @Published public var selectedGroupName: String = ""
    @Published public var groupSelections: [String: String] = [:]

    @Published public var latencies: [UUID: Int] = [:]
    @Published public var statuses: [UUID: ProxyStatus] = [:]
    @Published public var isTesting: Bool = false
    @Published public var testedCount: Int = 0
    @Published public var importStatusMessage: String?
    @Published public var lastImportSummary: YAMLImportSummary?

    // Search / sort
    @Published public var searchText: String = ""
    @Published public var sortOrder: ProxySortOrder = .name

    private let settings = SharedSettings()
    private let maxConcurrentTests = 6
    private var cancelTesting = false
    private let testingQueue = DispatchQueue(label: "com.rakib.tunnexa.proxytest", attributes: .concurrent)

    public init() {
        loadSavedConfig()
    }

    public var filteredProxies: [SOCKS5Proxy] {
        var result = proxies
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) || $0.host.lowercased().contains(query)
            }
        }
        switch sortOrder {
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .latency:
            result.sort { (latencies[$0.id] ?? Int.max) < (latencies[$1.id] ?? Int.max) }
        }
        return result
    }

    // MARK: - Persistence

    public func loadSavedConfig() {
        let config = settings.loadConfiguration()
        self.proxies = config?.proxies ?? []
        self.groups = config?.groups ?? []
        self.rules = config?.rules ?? []
        self.selectedProxyName = settings.selectedProxyName
        self.selectedGroupName = settings.selectedGroupName

        var selections: [String: String] = [:]
        for group in groups {
            selections[group.name] = settings.selectedGroupOption(for: group.name) ?? group.proxies.first ?? ""
        }
        self.groupSelections = selections
    }

    /// Atomic commit: builds a new configuration from the given parts,
    /// bumps the revision and stores it in a single write.
    private func commit(proxies: [SOCKS5Proxy], groups: [ProxyGroup], rules: [Rule]) {
        var config = ProxyConfiguration(proxies: proxies, groups: groups, rules: rules)
        config.schemaVersion = 1
        config.revision = (settings.loadConfiguration()?.revision ?? 0) + 1
        if settings.saveConfiguration(config) {
            loadSavedConfig()
        }
    }

    // MARK: - YAML Import

    public func importYAML(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            importYAMLText(content: content)
        } catch {
            self.importStatusMessage = "Failed to read file: \(error.localizedDescription)"
            SharedLogging.log("YAML file read failed: \(error.localizedDescription)", category: .yaml, level: .error)
        }
    }

    public func importYAMLText(content: String) {
        do {
            let summary = try YAMLParser.parseDetailed(content)
            commit(importedConfig: summary.configuration)

            if selectedProxyName.isEmpty, let firstProxy = proxies.first {
                selectProxy(firstProxy.name)
            }
            if selectedGroupName.isEmpty, let firstGroup = groups.first {
                selectGroup(firstGroup.name)
            }

            lastImportSummary = summary
            var message = "Import complete\n\n\(proxies.count) proxies\n\(groups.count) groups\n\(rules.count) rules"
            if summary.skippedProxies > 0 {
                message += "\n\(summary.skippedProxies) proxy(ies) skipped (unsupported type)"
            }
            if summary.skippedRules > 0 {
                message += "\n\(summary.skippedRules) rule(s) skipped (unsupported type)"
            }
            if !summary.warnings.isEmpty {
                message += "\n\nWarnings:\n" + summary.warnings.joined(separator: "\n")
            }
            importStatusMessage = message
            SharedLogging.log("Imported YAML: \(proxies.count) proxies, \(groups.count) groups, \(rules.count) rules.", category: .yaml)
        } catch {
            let description = (error as? YAMLParsingError)?.errorDescription ?? error.localizedDescription
            self.importStatusMessage = "Invalid configuration: \(description)"
            SharedLogging.log("YAML import failed: \(description)", category: .yaml, level: .error)
        }
    }

    /// Atomic import with stable IDs and credential preservation.
    private func commit(importedConfig: ProxyConfiguration) {
        // Build a stable identity map from the CURRENT configuration.
        var identityMap: [String: UUID] = [:]
        for proxy in proxies {
            identityMap[identityKey(name: proxy.name, host: proxy.host, port: proxy.port)] = proxy.id
        }

        var cleanedProxies: [SOCKS5Proxy] = []
        for proxy in importedConfig.proxies {
            let stableID = identityMap[identityKey(name: proxy.name, host: proxy.host, port: proxy.port)] ?? UUID()
            if let password = proxy.password, !password.isEmpty {
                KeychainHelper.shared.savePassword(password, forProxyId: stableID.uuidString)
            }
            cleanedProxies.append(SOCKS5Proxy(
                id: stableID,
                name: proxy.name,
                host: proxy.host,
                port: proxy.port,
                username: proxy.username,
                password: nil
            ))
        }
        commit(proxies: cleanedProxies, groups: importedConfig.groups, rules: importedConfig.rules)
    }

    private func identityKey(name: String, host: String, port: Int) -> String {
        return "\(name)|\(host)|\(port)"
    }

    public func importYAMLFromURL(urlString: String, completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            completion(false, "Invalid URL format")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Clash/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    completion(false, "Download failed: \(error.localizedDescription)")
                    return
                }
                guard let data = data, let content = String(data: data, encoding: .utf8) else {
                    completion(false, "Unable to decode text from server response.")
                    return
                }
                self.importYAMLText(content: content)
                completion(true, self.importStatusMessage ?? "Import complete")
            }
        }.resume()
    }

    // MARK: - Manual Proxy CRUD

    public func addManualProxy(name: String, host: String, port: Int, username: String?, password: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "\(trimmedHost):\(port)" : trimmedName
        let cleanUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)

        let newProxy = SOCKS5Proxy(
            id: UUID(),
            name: finalName,
            host: trimmedHost,
            port: port,
            username: cleanUsername?.isEmpty == false ? cleanUsername : nil,
            password: nil
        )

        if let pwd = cleanPassword, !pwd.isEmpty {
            KeychainHelper.shared.savePassword(pwd, forProxyId: newProxy.id.uuidString)
        }

        var updatedProxies = self.proxies
        if let index = updatedProxies.firstIndex(where: { $0.name == finalName }) {
            updatedProxies[index] = newProxy
        } else {
            updatedProxies.append(newProxy)
        }
        commit(proxies: updatedProxies, groups: self.groups, rules: self.rules)

        if selectedProxyName.isEmpty {
            selectProxy(newProxy.name)
        }
        SharedLogging.log("Added manual SOCKS5 proxy: \(finalName) (\(trimmedHost):\(port))", category: .proxy)
    }

    public func updateManualProxy(id: UUID, name: String, host: String, port: Int, username: String?, password: String?) {
        guard let index = proxies.firstIndex(where: { $0.id == id }) else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "\(trimmedHost):\(port)" : trimmedName
        let cleanUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)

        let updatedProxy = SOCKS5Proxy(
            id: id,
            name: finalName,
            host: trimmedHost,
            port: port,
            username: cleanUsername?.isEmpty == false ? cleanUsername : nil,
            password: nil
        )

        if let pwd = cleanPassword, !pwd.isEmpty {
            KeychainHelper.shared.savePassword(pwd, forProxyId: id.uuidString)
        }

        var updatedList = self.proxies
        let oldName = updatedList[index].name
        updatedList[index] = updatedProxy
        commit(proxies: updatedList, groups: self.groups, rules: self.rules)

        if selectedProxyName == oldName {
            selectProxy(finalName)
        }
        SharedLogging.log("Updated SOCKS5 proxy: \(finalName)", category: .proxy)
    }

    public func deleteProxy(id: UUID) {
        if let proxy = proxies.first(where: { $0.id == id }) {
            KeychainHelper.shared.deletePassword(forProxyId: id.uuidString)
            let remaining = proxies.filter { $0.id != id }
            commit(proxies: remaining, groups: self.groups, rules: self.rules)

            if selectedProxyName == proxy.name {
                let fallback = remaining.first?.name ?? ""
                selectedProxyName = fallback
                settings.selectedProxyName = fallback
            }
            SharedLogging.log("Deleted proxy: \(proxy.name)", category: .proxy)
        }
    }

    public func deleteProxies(at offsets: IndexSet) {
        for index in offsets {
            let proxy = proxies[index]
            KeychainHelper.shared.deletePassword(forProxyId: proxy.id.uuidString)
        }
        var remaining = proxies
        remaining.remove(atOffsets: offsets)
        commit(proxies: remaining, groups: self.groups, rules: self.rules)

        if !remaining.contains(where: { $0.name == selectedProxyName }) {
            let fallback = remaining.first?.name ?? ""
            selectedProxyName = fallback
            settings.selectedProxyName = fallback
        }
    }

    // MARK: - Selection

    public func selectProxy(_ name: String) {
        self.selectedProxyName = name
        self.selectedGroupName = ""
        settings.selectedProxyName = name
        settings.selectedGroupName = ""
        SharedLogging.log("Selected proxy: \(name)", category: .proxy)
    }

    public func selectGroup(_ name: String) {
        self.selectedGroupName = name
        self.selectedProxyName = ""
        settings.selectedGroupName = name
        settings.selectedProxyName = ""
        SharedLogging.log("Selected group: \(name)", category: .proxy)
    }

    public func selectGroupOption(groupName: String, optionName: String) {
        groupSelections[groupName] = optionName
        settings.setSelectedGroupOption(optionName, for: groupName)
        SharedLogging.log("Group '\(groupName)' set to option: \(optionName)", category: .proxy)
    }

    // MARK: - Latency Testing

    public func testLatency(for proxy: SOCKS5Proxy) {
        let proxyId = proxy.id
        self.statuses[proxyId] = .checking
        let password = KeychainHelper.shared.loadPassword(forProxyId: proxyId.uuidString)

        ProxyHealthTester.testLatency(proxy: proxy, password: password) { [weak self] result in
            guard let self = self else { return }
            self.apply(result)
        }
    }

    /// Tests all proxies with bounded concurrency, live progress and cancel.
    public func testAllLatencies() {
        guard !proxies.isEmpty else { return }
        cancelTesting = false
        isTesting = true
        testedCount = 0
        for proxy in proxies {
            statuses[proxy.id] = .checking
        }

        let semaphore = DispatchSemaphore(value: maxConcurrentTests)

        for proxy in proxies {
            testingQueue.async { [weak self] in
                guard let self = self else { return }
                semaphore.wait()
                guard !self.cancelTesting else {
                    semaphore.signal()
                    return
                }
                let password = KeychainHelper.shared.loadPassword(forProxyId: proxy.id.uuidString)
                ProxyHealthTester.testLatency(proxy: proxy, password: password) { result in
                    DispatchQueue.main.async {
                        self.apply(result)
                        self.testedCount += 1
                        if self.testedCount >= self.proxies.count {
                            self.isTesting = false
                            SharedLogging.log("Completed latency checks for \(self.proxies.count) proxies.", category: .proxy)
                        }
                        semaphore.signal()
                    }
                }
            }
        }
    }

    public func cancelLatencyTests() {
        cancelTesting = true
        isTesting = false
        SharedLogging.log("Latency tests cancelled by user.", category: .proxy)
    }

    private func apply(_ result: HealthTestResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.latencies[result.proxyId] = result.totalLatencyMs
            switch result.status {
            case .online:
                self.statuses[result.proxyId] = (result.totalLatencyMs ?? 999) < 150 ? .online : .slow
            case .authFailed:
                self.statuses[result.proxyId] = .authFailed
            case .timeout:
                self.statuses[result.proxyId] = .timeout
            case .protocolError:
                self.statuses[result.proxyId] = .protocolError
            case .connFailed:
                self.statuses[result.proxyId] = .connFailed
            case .checking, .unknown:
                self.statuses[result.proxyId] = .unknown
            }
        }
    }
}