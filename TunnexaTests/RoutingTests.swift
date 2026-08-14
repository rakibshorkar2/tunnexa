import XCTest
@testable import Tunnexa
@testable import TunnexaPacketTunnel

final class RoutingTests: XCTestCase {
    
    var proxyServer: LocalProxyServer!
    var sharedDefaults: UserDefaults!
    
    override func setUp() {
        super.setUp()
        sharedDefaults = UserDefaults(suiteName: "group.com.rakib.tunnexa_test") ?? UserDefaults.standard
        proxyServer = LocalProxyServer(port: 10808, sharedDefaults: sharedDefaults)
    }
    
    override func tearDown() {
        proxyServer = nil
        sharedDefaults.removePersistentDomain(forName: "group.com.rakib.tunnexa_test")
        sharedDefaults = nil
        super.tearDown()
    }
    
    func testRuleMatchingDomainSuffix() {
        let rules = [
            Rule(type: .domainSuffix, payload: "google.com", target: "BypassEmpire"),
            Rule(type: .match, payload: nil, target: "DIRECT")
        ]
        let config = ProxyConfiguration(
            proxies: [SOCKS5Proxy(name: "Server-1", host: "127.0.0.1", port: 1080)],
            groups: [],
            rules: rules
        )
        proxyServer.config = config
        
        // Host ends with google.com -> BypassEmpire
        let route1 = proxyServer.evaluateRules(host: "www.google.com", port: 443, cmd: 1)
        XCTAssertEqual(route1, "BypassEmpire")
        
        // Host ends with maps.google.com -> BypassEmpire
        let route2 = proxyServer.evaluateRules(host: "maps.google.com", port: 80, cmd: 1)
        XCTAssertEqual(route2, "BypassEmpire")
        
        // Host is bing.com -> MATCH rule -> DIRECT
        let route3 = proxyServer.evaluateRules(host: "bing.com", port: 443, cmd: 1)
        XCTAssertEqual(route3, "DIRECT")
    }
    
    func testRuleMatchingNetwork() {
        let rules = [
            Rule(type: .network, payload: "UDP", target: "DIRECT"),
            Rule(type: .match, payload: nil, target: "ProxyGroup")
        ]
        let config = ProxyConfiguration(proxies: [], groups: [], rules: rules)
        proxyServer.config = config
        
        // Command 3 = UDP ASSOCIATE -> DIRECT
        let route1 = proxyServer.evaluateRules(host: "anyhost.com", port: 53, cmd: 3)
        XCTAssertEqual(route1, "DIRECT")
        
        // Command 1 = TCP CONNECT -> ProxyGroup
        let route2 = proxyServer.evaluateRules(host: "anyhost.com", port: 80, cmd: 1)
        XCTAssertEqual(route2, "ProxyGroup")
    }
    
    func testLoadBalanceRoundRobin() {
        let proxies = [
            SOCKS5Proxy(name: "Server-1", host: "127.0.0.1", port: 1081),
            SOCKS5Proxy(name: "Server-2", host: "127.0.0.1", port: 1082),
            SOCKS5Proxy(name: "Server-3", host: "127.0.0.1", port: 1083)
        ]
        
        let groups = [
            ProxyGroup(
                name: "LoadBalancer",
                type: .loadBalance,
                proxies: ["Server-1", "Server-2", "Server-3"],
                url: nil,
                interval: nil,
                strategy: "round-robin"
            )
        ]
        
        let config = ProxyConfiguration(proxies: proxies, groups: groups, rules: [])
        proxyServer.config = config
        
        guard let group = config.groups.first else {
            XCTFail("Missing load-balance group configuration")
            return
        }
        
        // 1st connection -> Server-1
        let p1 = proxyServer.resolveGroup(group)
        XCTAssertEqual(p1?.name, "Server-1")
        
        // 2nd connection -> Server-2
        let p2 = proxyServer.resolveGroup(group)
        XCTAssertEqual(p2?.name, "Server-2")
        
        // 3rd connection -> Server-3
        let p3 = proxyServer.resolveGroup(group)
        XCTAssertEqual(p3?.name, "Server-3")
        
        // 4th connection -> Server-1 (cycles back)
        let p4 = proxyServer.resolveGroup(group)
        XCTAssertEqual(p4?.name, "Server-1")
    }
}
