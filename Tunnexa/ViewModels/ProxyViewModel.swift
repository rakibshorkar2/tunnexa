import Foundation
import SwiftUI

public class ProxyViewModel: ObservableObject {
    @Published public var proxies: [SOCKS5Proxy] = []
    @Published public var groups: [ProxyGroup] = []
    @Published public var rules: [Rule] = []
    
    @Published public var selectedProxyName: String = ""
    @Published public var selectedGroupName: String = ""
    @Published public var groupSelections: [String: String] = [:] // Group Name -> Option Selected
    
    @Published public var latencies: [UUID: Int] = [:]
    @Published public var statuses: [UUID: ProxyStatus] = [:]
    @Published public var isTesting: Bool = false
    @Published public var importStatusMessage: String?
    
    private let sharedDefaults: UserDefaults = UserDefaults(suiteName: "group.com.rakib.tunnexa") ?? .standard
    
    public init() {
        loadSavedConfig()
    }
    
    public func loadSavedConfig() {
        if let data = sharedDefaults.data(forKey: "proxy_config"),
           let parsed = try? JSONDecoder().decode(ProxyConfiguration.self, from: data) {
            self.proxies = parsed.proxies
            self.groups = parsed.groups
            self.rules = parsed.rules
        }
        
        self.selectedProxyName = sharedDefaults.string(forKey: "selected_proxy") ?? ""
        self.selectedGroupName = sharedDefaults.string(forKey: "selected_group") ?? ""
        
        // Load group choices
        var selections: [String: String] = [:]
        for group in groups {
            let key = "selected_group_option_\(group.name)"
            selections[group.name] = sharedDefaults.string(forKey: key) ?? group.proxies.first ?? ""
        }
        self.groupSelections = selections
    }
    
    private func saveConfig(proxies: [SOCKS5Proxy], groups: [ProxyGroup], rules: [Rule]) {
        let config = ProxyConfiguration(proxies: proxies, groups: groups, rules: rules)
        if let encoded = try? JSONEncoder().encode(config) {
            sharedDefaults.set(encoded, forKey: "proxy_config")
        }
        loadSavedConfig()
    }
    
    // MARK: - YAML Import Methods
    
    public func importYAML(from url: URL) {
        // Access security scoped resource if needed (e.g. from file picker)
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
            SharedLogging.log("YAML File Read failed: \(error.localizedDescription)", category: .yaml)
        }
    }
    
    public func importYAMLText(content: String) {
        do {
            let config = try YAMLParser.parse(content)
            
            // Store credentials securely in Keychain, and keep clean proxies in state
            var cleanedProxies: [SOCKS5Proxy] = []
            for proxy in config.proxies {
                if let pwd = proxy.password {
                    KeychainHelper.shared.setPassword(pwd, forProxyId: proxy.id.uuidString)
                }
                cleanedProxies.append(SOCKS5Proxy(
                    id: proxy.id,
                    name: proxy.name,
                    host: proxy.host,
                    port: proxy.port,
                    username: proxy.username,
                    password: nil
                ))
            }
            
            saveConfig(proxies: cleanedProxies, groups: config.groups, rules: config.rules)
            
            if selectedProxyName.isEmpty, let firstProxy = cleanedProxies.first {
                selectProxy(firstProxy.name)
            }
            if selectedGroupName.isEmpty, let firstGroup = config.groups.first {
                selectGroup(firstGroup.name)
            }
            
            self.importStatusMessage = "Import complete\n\n\(cleanedProxies.count) proxies found\n\(config.groups.count) proxy groups found\n\(config.rules.count) rules found"
            SharedLogging.log("Successfully imported YAML configuration. Proxies count: \(cleanedProxies.count)", category: .yaml)
        } catch {
            self.importStatusMessage = "Invalid YAML: \(error.localizedDescription)"
            SharedLogging.log("YAML Import failed: \(error.localizedDescription)", category: .yaml)
        }
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
            KeychainHelper.shared.setPassword(pwd, forProxyId: newProxy.id.uuidString)
        }
        
        var updatedProxies = self.proxies
        // If name duplicate exists, update it or append
        if let index = updatedProxies.firstIndex(where: { $0.name == finalName }) {
            updatedProxies[index] = newProxy
        } else {
            updatedProxies.append(newProxy)
        }
        
        saveConfig(proxies: updatedProxies, groups: self.groups, rules: self.rules)
        
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
            KeychainHelper.shared.setPassword(pwd, forProxyId: id.uuidString)
        }
        
        var updatedList = self.proxies
        let oldName = updatedList[index].name
        updatedList[index] = updatedProxy
        
        saveConfig(proxies: updatedList, groups: self.groups, rules: self.rules)
        
        if selectedProxyName == oldName {
            selectProxy(finalName)
        }
        
        SharedLogging.log("Updated SOCKS5 proxy: \(finalName)", category: .proxy)
    }
    
    public func deleteProxy(id: UUID) {
        if let proxy = proxies.first(where: { $0.id == id }) {
            KeychainHelper.shared.deletePassword(forProxyId: id.uuidString)
            let remaining = proxies.filter { $0.id != id }
            saveConfig(proxies: remaining, groups: self.groups, rules: self.rules)
            
            if selectedProxyName == proxy.name {
                selectedProxyName = remaining.first?.name ?? ""
                sharedDefaults.set(selectedProxyName, forKey: "selected_proxy")
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
        saveConfig(proxies: remaining, groups: self.groups, rules: self.rules)
        
        if !remaining.contains(where: { $0.name == selectedProxyName }) {
            selectedProxyName = remaining.first?.name ?? ""
            sharedDefaults.set(selectedProxyName, forKey: "selected_proxy")
        }
    }
    
    // MARK: - Selection
    
    public func selectProxy(_ name: String) {
        self.selectedProxyName = name
        self.selectedGroupName = ""
        sharedDefaults.set(name, forKey: "selected_proxy")
        sharedDefaults.removeObject(forKey: "selected_group")
        SharedLogging.log("Selected manual proxy: \(name)", category: .proxy)
    }
    
    public func selectGroup(_ name: String) {
        self.selectedGroupName = name
        self.selectedProxyName = ""
        sharedDefaults.set(name, forKey: "selected_group")
        sharedDefaults.removeObject(forKey: "selected_proxy")
        SharedLogging.log("Selected proxy group: \(name)", category: .proxy)
    }
    
    public func selectGroupOption(groupName: String, optionName: String) {
        groupSelections[groupName] = optionName
        sharedDefaults.set(optionName, forKey: "selected_group_option_\(groupName)")
        SharedLogging.log("Group '\(groupName)' set to option: \(optionName)", category: .proxy)
    }
    
    // MARK: - Latency Testing
    
    public func testLatency(for proxy: SOCKS5Proxy) {
        let proxyId = proxy.id
        self.statuses[proxyId] = .checking
        
        let testProxy = SOCKS5Proxy(
            id: proxy.id,
            name: proxy.name,
            host: proxy.host,
            port: proxy.port,
            username: proxy.username,
            password: KeychainHelper.shared.getPassword(forProxyId: proxy.id.uuidString)
        )
        
        ProxyHealthTester.testLatency(proxy: testProxy) { [weak self] latency, status in
            guard let self = self else { return }
            self.latencies[proxyId] = latency
            
            if status == "Online" {
                if let latency = latency {
                    self.statuses[proxyId] = latency < 150 ? .online : .slow
                }
            } else if status == "Authentication Failed" {
                self.statuses[proxyId] = .authFailed
            } else if status == "Timeout" {
                self.statuses[proxyId] = .timeout
            } else {
                self.statuses[proxyId] = .connFailed
            }
        }
    }
    
    public func testAllLatencies() {
        guard !proxies.isEmpty else { return }
        isTesting = true
        
        let group = DispatchGroup()
        for proxy in proxies {
            group.enter()
            let testProxy = SOCKS5Proxy(
                id: proxy.id,
                name: proxy.name,
                host: proxy.host,
                port: proxy.port,
                username: proxy.username,
                password: KeychainHelper.shared.getPassword(forProxyId: proxy.id.uuidString)
            )
            
            self.statuses[proxy.id] = .checking
            ProxyHealthTester.testLatency(proxy: testProxy) { [weak self] latency, status in
                guard let self = self else {
                    group.leave()
                    return
                }
                self.latencies[proxy.id] = latency
                if status == "Online" {
                    self.statuses[proxy.id] = (latency ?? 999) < 150 ? .online : .slow
                } else if status == "Authentication Failed" {
                    self.statuses[proxy.id] = .authFailed
                } else if status == "Timeout" {
                    self.statuses[proxy.id] = .timeout
                } else {
                    self.statuses[proxy.id] = .connFailed
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.isTesting = false
            SharedLogging.log("Completed latency checks for all imported proxies.", category: .proxy)
        }
    }
}
