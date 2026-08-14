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
    
    private let sharedDefaults = UserDefaults(suiteName: "group.com.rakib.tunnexa")!
    
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
            let config = try YAMLParser.parse(content)
            
            // 1. Store credentials securely in Keychain, and remove them from the persistent config copy
            var cleanedProxies: [SOCKS5Proxy] = []
            for proxy in config.proxies {
                if let pwd = proxy.password {
                    KeychainHelper.shared.setPassword(pwd, forProxyId: proxy.id.uuidString)
                }
                // Save without password in the main array for extra security
                cleanedProxies.append(SOCKS5Proxy(id: proxy.id, name: proxy.name, host: proxy.host, port: proxy.port, username: proxy.username, password: nil))
            }
            
            let sanitizedConfig = ProxyConfiguration(proxies: cleanedProxies, groups: config.groups, rules: config.rules)
            
            // 2. Save sanitized config to shared UserDefaults
            if let encoded = try? JSONEncoder().encode(sanitizedConfig) {
                sharedDefaults.set(encoded, forKey: "proxy_config")
            }
            
            // 3. Set default selections if empty
            if selectedProxyName.isEmpty, let firstProxy = cleanedProxies.first {
                selectProxy(firstProxy.name)
            }
            if selectedGroupName.isEmpty, let firstGroup = config.groups.first {
                selectGroup(firstGroup.name)
            }
            
            // Load and update UI state
            self.loadSavedConfig()
            
            // Formulate import status message
            self.importStatusMessage = "Import complete\n\n\(cleanedProxies.count) proxies found\n\(config.groups.count) proxy groups found\n\(config.rules.count) rules found"
            
            SharedLogging.log("Successfully imported YAML configuration. Proxies count: \(cleanedProxies.count)", category: .yaml)
        } catch {
            self.importStatusMessage = "Invalid YAML: \(error.localizedDescription)"
            SharedLogging.log("YAML Import failed: \(error.localizedDescription)", category: .yaml)
        }
    }
    
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
        
        // Notify local proxy if running (since it reads shared defaults)
    }
    
    public func testLatency(for proxy: SOCKS5Proxy) {
        let proxyId = proxy.id
        self.statuses[proxyId] = .checking
        
        // We need to resolve password for latency testing
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
                    if latency < 150 {
                        self.statuses[proxyId] = .online
                    } else {
                        self.statuses[proxyId] = .slow
                    }
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
