import XCTest
@testable import Tunnexa

final class RoutingTests: XCTestCase {

    var proxyServer: LocalProxyServer!
    var testSettings: SharedSettings!
    var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.rakib.tunnexa_test_\(UUID().uuidString)"
        testSettings = SharedSettings(suiteName: suiteName)
        proxyServer = LocalProxyServer(port: 10808, settings: testSettings)
    }

    override func tearDown() {
        proxyServer.stop()
        proxyServer = nil
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        testSettings = nil
        super.tearDown()
    }

    private func makeConfig(proxies: [SOCKS5Proxy], groups: [ProxyGroup], rules: [Rule]) -> ProxyConfiguration {
        return ProxyConfiguration(proxies: proxies, groups: groups, rules: rules)
    }

    // MARK: - Rule matching

    func testRuleMatchingDomainSuffix() {
        let rules = [
            Rule(type: .domainSuffix, payload: "google.com", target: "BypassEmpire"),
            Rule(type: .match, payload: nil, target: "DIRECT")
        ]
        proxyServer.config = makeConfig(
            proxies: [SOCKS5Proxy(name: "Server-1", host: "127.0.0.1", port: 1080)],
            groups: [],
            rules: rules
        )

        XCTAssertEqual(proxyServer.evaluateRules(host: "www.google.com", port: 443, protocolType: .tcp), "BypassEmpire")
        XCTAssertEqual(proxyServer.evaluateRules(host: "maps.google.com", port: 80, protocolType: .tcp), "BypassEmpire")
        XCTAssertEqual(proxyServer.evaluateRules(host: "google.com", port: 443, protocolType: .tcp), "BypassEmpire")
        XCTAssertEqual(proxyServer.evaluateRules(host: "bing.com", port: 443, protocolType: .tcp), "DIRECT")
    }

    func testDomainSuffixRespectsLabelBoundary() {
        let rules = [
            Rule(type: .domainSuffix, payload: "google.com", target: "PROXY"),
            Rule(type: .match, payload: nil, target: "DIRECT")
        ]
        proxyServer.config = makeConfig(proxies: [], groups: [], rules: rules)

        XCTAssertEqual(proxyServer.evaluateRules(host: "evilgoogle.com", port: 443, protocolType: .tcp), "DIRECT", "evilgoogle.com must NOT match google.com suffix")
        XCTAssertEqual(proxyServer.evaluateRules(host: "notgoogle.com.evil", port: 443, protocolType: .tcp), "DIRECT")
    }

    func testRuleMatchingNetworkProtocol() {
        let rules = [
            Rule(type: .network, payload: "UDP", target: "DIRECT"),
            Rule(type: .match, payload: nil, target: "ProxyGroup")
        ]
        proxyServer.config = makeConfig(proxies: [], groups: [], rules: rules)

        XCTAssertEqual(proxyServer.evaluateRules(host: "anyhost.com", port: 53, protocolType: .udp), "DIRECT")
        XCTAssertEqual(proxyServer.evaluateRules(host: "anyhost.com", port: 80, protocolType: .tcp), "ProxyGroup")
    }

    func testRuleMatchingCIDR() {
        let rules = [
            Rule(type: .network, payload: "192.168.0.0/16", target: "DIRECT"),
            Rule(type: .network, payload: "10.0.0.1", target: "BLOCK"),
            Rule(type: .match, payload: nil, target: "PROXY")
        ]
        proxyServer.config = makeConfig(proxies: [], groups: [], rules: rules)

        XCTAssertEqual(proxyServer.evaluateRules(host: "192.168.5.2", port: 443, protocolType: .tcp), "DIRECT")
        XCTAssertEqual(proxyServer.evaluateRules(host: "10.0.0.1", port: 443, protocolType: .tcp), "BLOCK")
        XCTAssertEqual(proxyServer.evaluateRules(host: "8.8.8.8", port: 443, protocolType: .tcp), "PROXY")
    }

    func testNetworkRuleMatchesResolvedDomainAddresses() {
        let rules = [
            Rule(type: .network, payload: "192.168.0.0/16", target: "DIRECT"),
            Rule(type: .match, payload: nil, target: "PROXY")
        ]
        proxyServer.config = makeConfig(proxies: [], groups: [], rules: rules)

        // Domain host with known resolved IP inside the CIDR.
        XCTAssertEqual(
            proxyServer.evaluateRules(host: "router.local", port: 80, protocolType: .tcp, resolvedAddresses: ["192.168.0.10"]),
            "DIRECT"
        )
        XCTAssertEqual(
            proxyServer.evaluateRules(host: "router.local", port: 80, protocolType: .tcp, resolvedAddresses: ["8.8.8.8"]),
            "PROXY"
        )
    }

    func testRuleMatchingCaseInsensitive() {
        let rules = [
            Rule(type: .domainSuffix, payload: "Google.COM", target: "PROXY"),
            Rule(type: .match, payload: nil, target: "DIRECT")
        ]
        proxyServer.config = makeConfig(proxies: [], groups: [], rules: rules)
        XCTAssertEqual(proxyServer.evaluateRules(host: "WWW.GOOGLE.COM", port: 443, protocolType: .tcp), "PROXY")
    }

    // MARK: - Fallback & fail-closed behaviour

    func testNoSelectionFallsBackToBlocked() {
        let config = makeConfig(proxies: [SOCKS5Proxy(name: "Server-1", host: "127.0.0.1", port: 1080)], groups: [], rules: [])
        proxyServer.config = config
        testSettings.selectedProxyName = ""
        testSettings.selectedGroupName = ""
        proxyServer.loadConfig()

        XCTAssertEqual(proxyServer.resolveRoute(host: "example.com", port: 443, protocolType: .tcp), .blocked,
                       "Without a selection or a matching rule the route must be BLOCKED, never implicitly DIRECT.")
    }

    func testDirectAndBlockTargetsResolve() {
        let proxies = [SOCKS5Proxy(name: "Server-1", host: "127.0.0.1", port: 1080)]
        proxyServer.config = makeConfig(proxies: proxies, groups: [], rules: [])
        XCTAssertEqual(proxyServer.resolveTarget("DIRECT"), .direct)
        XCTAssertEqual(proxyServer.resolveTarget("BLOCK"), .blocked)
        XCTAssertEqual(proxyServer.resolveTarget("Server-1"), .proxy(proxies[0]),
                       "Resolution must return the config's own proxy instance (stable id), not a copy")
        if case .failed = proxyServer.resolveTarget("DoesNotExist") {
            // expected
        } else {
            XCTFail("Unknown target must resolve to failure")
        }
    }

    // MARK: - Groups

    func testLoadBalanceRoundRobin() {
        let proxies = [
            SOCKS5Proxy(name: "Server-1", host: "127.0.0.1", port: 1081),
            SOCKS5Proxy(name: "Server-2", host: "127.0.0.1", port: 1082),
            SOCKS5Proxy(name: "Server-3", host: "127.0.0.1", port: 1083)
        ]
        let groups = [
            ProxyGroup(name: "LoadBalancer", type: .loadBalance, proxies: ["Server-1", "Server-2", "Server-3"],
                       url: nil, interval: nil, strategy: "round-robin")
        ]
        proxyServer.config = makeConfig(proxies: proxies, groups: groups, rules: [])

        guard let group = groups.first else {
            XCTFail("Missing load-balance group")
            return
        }
        XCTAssertEqual(proxyServer.resolveGroup(group), .proxy(proxies[0]))
        XCTAssertEqual(proxyServer.resolveGroup(group), .proxy(proxies[1]))
        XCTAssertEqual(proxyServer.resolveGroup(group), .proxy(proxies[2]))
        XCTAssertEqual(proxyServer.resolveGroup(group), .proxy(proxies[0]))
    }

    func testLoadBalanceRoundRobinSkipsUnresolvableMembers() {
        let proxies = [SOCKS5Proxy(name: "Server-1", host: "127.0.0.1", port: 1081)]
        let groups = [
            ProxyGroup(name: "LB", type: .loadBalance, proxies: ["Missing-1", "Server-1", "Missing-2"],
                       url: nil, interval: nil, strategy: "round-robin")
        ]
        proxyServer.config = makeConfig(proxies: proxies, groups: groups, rules: [])
        guard let group = groups.first else { return XCTFail("No group") }

        // All three rotations must land on the only resolvable member.
        XCTAssertEqual(proxyServer.resolveGroup(group), .proxy(proxies[0]))
        XCTAssertEqual(proxyServer.resolveGroup(group), .proxy(proxies[0]))
        XCTAssertEqual(proxyServer.resolveGroup(group), .proxy(proxies[0]))
    }

    func testLoadBalanceIndexResetsOnMembershipChange() {
        let proxies = [
            SOCKS5Proxy(name: "Server-1", host: "127.0.0.1", port: 1081),
            SOCKS5Proxy(name: "Server-2", host: "127.0.0.1", port: 1082)
        ]
        let original = [ProxyGroup(name: "LB", type: .loadBalance, proxies: ["Server-1", "Server-2"], url: nil, interval: nil, strategy: "round-robin")]
        proxyServer.config = makeConfig(proxies: proxies, groups: original, rules: [])
        guard let group = original.first else { return XCTFail("No group") }

        _ = proxyServer.resolveGroup(group) // -> Server-1
        _ = proxyServer.resolveGroup(group) // -> Server-2

        // Membership changes -> signature reset -> index restarts at 0.
        let changed = [ProxyGroup(name: "LB", type: .loadBalance, proxies: ["Server-2", "Server-1"], url: nil, interval: nil, strategy: "round-robin")]
        proxyServer.config = makeConfig(proxies: proxies, groups: changed, rules: [])
        guard let changedGroup = changed.first else { return XCTFail("No group") }

        XCTAssertEqual(proxyServer.resolveGroup(changedGroup), .proxy(proxies[1]), "Index must reset after membership change")
    }

    func testSelectGroupRespectsStoredOption() {
        let proxies = [
            SOCKS5Proxy(name: "Server-1", host: "127.0.0.1", port: 1081),
            SOCKS5Proxy(name: "Server-2", host: "127.0.0.1", port: 1082)
        ]
        let groups = [ProxyGroup(name: "Select", type: .select, proxies: ["Server-1", "Server-2"], url: nil, interval: nil, strategy: nil)]
        proxyServer.config = makeConfig(proxies: proxies, groups: groups, rules: [])
        testSettings.setSelectedGroupOption("Server-2", for: "Select")

        guard let group = groups.first else { return XCTFail("No group") }
        XCTAssertEqual(proxyServer.resolveGroup(group), .proxy(proxies[1]))
    }

    func testCircularGroupReferenceDetected() {
        let proxies = [SOCKS5Proxy(name: "Server-1", host: "127.0.0.1", port: 1081)]
        let groups = [
            ProxyGroup(name: "A", type: .select, proxies: ["B"], url: nil, interval: nil, strategy: nil),
            ProxyGroup(name: "B", type: .select, proxies: ["A"], url: nil, interval: nil, strategy: nil)
        ]
        proxyServer.config = makeConfig(proxies: proxies, groups: groups, rules: [])
        guard let a = groups.first else { return XCTFail("No group") }

        XCTAssertEqual(proxyServer.resolveGroup(a), .noMembers, "Circular references must not recurse forever")
    }

    func testGroupWithDirectAndBlockedMembers() {
        let proxies = [SOCKS5Proxy(name: "Server-1", host: "127.0.0.1", port: 1081)]
        let groups = [
            ProxyGroup(name: "G", type: .select, proxies: [RouteDirect, RouteBlocked], url: nil, interval: nil, strategy: nil)
        ]
        proxyServer.config = makeConfig(proxies: proxies, groups: groups, rules: [])
        guard let group = groups.first else { return XCTFail("No group") }
        XCTAssertEqual(proxyServer.resolveGroup(group), .direct)
    }

    // MARK: - Address matcher

    func testNetworkAddressMatcher() {
        XCTAssertTrue(NetworkAddressMatcher.isIPv4("192.168.1.1"))
        XCTAssertFalse(NetworkAddressMatcher.isIPv4("256.1.1.1"))
        XCTAssertFalse(NetworkAddressMatcher.isIPv4("example.com"))

        XCTAssertTrue(NetworkAddressMatcher.isIPv6("2001:db8::1"))
        XCTAssertTrue(NetworkAddressMatcher.isIPv6("::1"))
        XCTAssertTrue(NetworkAddressMatcher.isIPv6("fe80::1:2:3"))
        XCTAssertFalse(NetworkAddressMatcher.isIPv6("2001:db8::1::2"))

        XCTAssertTrue(NetworkAddressMatcher.isCIDR("192.168.0.0/16"))
        XCTAssertFalse(NetworkAddressMatcher.isCIDR("192.168.0.0/33"))
        XCTAssertTrue(NetworkAddressMatcher.isCIDR("2001:db8::/32"))

        XCTAssertTrue(NetworkAddressMatcher.cidrContains(address: "192.168.5.2", cidr: "192.168.0.0/16"))
        XCTAssertFalse(NetworkAddressMatcher.cidrContains(address: "10.0.0.2", cidr: "192.168.0.0/16"))
        XCTAssertTrue(NetworkAddressMatcher.cidrContains(address: "2001:db8:1::1", cidr: "2001:db8::/32"))
        XCTAssertFalse(NetworkAddressMatcher.cidrContains(address: "2001:db9::1", cidr: "2001:db8::/32"))

        XCTAssertEqual(NetworkAddressMatcher.ipv4ToUInt32("127.0.0.1"), 0x7F000001)
        XCTAssertEqual(NetworkAddressMatcher.ipv6String(fromBytes: Data([0x20, 0x01, 0x0d, 0xb8])), "2001:db8:0:0:0:0:0:0")
    }

    func testIPv4AndIPv6StringEncoding() {
        let v4 = NetworkAddressMatcher.ipv4StringToBytes("192.168.0.1")
        XCTAssertEqual(v4, Data([192, 168, 0, 1]))
        XCTAssertNil(NetworkAddressMatcher.ipv4StringToBytes("192.168.0"))

        let v6 = NetworkAddressMatcher.ipv6StringToBytes("2001:db8::1")
        XCTAssertEqual(v6?.count, 16)
        XCTAssertEqual(v6?.prefix(4), Data([0x20, 0x01, 0x0d, 0xb8]))
        XCTAssertEqual(v6?.suffix(2), Data([0x00, 0x01]))
    }
}
