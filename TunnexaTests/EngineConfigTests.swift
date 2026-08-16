import XCTest
@testable import Tunnexa

/// Hermetic tests for the engine configuration builder.
///
/// The contract is verified against hev-socks5-tunnel's config parser:
///  - `tunnel` has no `fd` key (the engine receives the descriptor directly);
///  - `socks5` carries no `udp` key (UDP uses SOCKS5 ASSOCIATE, not UDP-in-UDP);
///  - `misc.task-stack-size` reflects the engine's enforced floor.
final class EngineConfigTests: XCTestCase {

    private let defaultTuning = EngineConfigBuilder.Tuning()

    func testNoFdKeyIsEmitted() {
        let config = EngineConfigBuilder.build(mtu: 1500, isIPv6Enabled: false, localPort: 10808)
        XCTAssertFalse(config.contains("fd:"), "The engine ignores an fd config key; emitting one is misleading.")
        XCTAssertFalse(config.contains("tunFd"))
        XCTAssertFalse(config.contains("tun0"))
    }

    func testNoUdpKeyIsEmitted() {
        let config = EngineConfigBuilder.build(mtu: 1500, isIPv6Enabled: false, localPort: 10808)
        XCTAssertFalse(config.contains("udp:"), "udp: udp selects UDP-in-UDP, which the local dispatcher does not implement.")
    }

    func testNoTunnelNameOrAddressKeysAreEmitted() {
        let config = EngineConfigBuilder.build(mtu: 1500, isIPv6Enabled: true, localPort: 10808)
        XCTAssertFalse(config.contains("name:"))
        XCTAssertFalse(config.contains("ipv4:"), "With an external descriptor the engine ignores tunnel ipv4.")
        XCTAssertFalse(config.contains("ipv6:"), "With an external descriptor the engine ignores tunnel ipv6.")
        XCTAssertFalse(config.contains("fc00::1"))
    }

    func testDispatcherEndpointIsConfigured() {
        let config = EngineConfigBuilder.build(mtu: 1500, isIPv6Enabled: false, localPort: 10808)
        XCTAssertTrue(config.contains("address: 127.0.0.1"))
        XCTAssertTrue(config.contains("port: 10808"))
    }

    func testMtuIsIncluded() {
        let config = EngineConfigBuilder.build(mtu: 9000, isIPv6Enabled: false, localPort: 10808)
        XCTAssertTrue(config.contains("mtu: 9000"), "The engine uses tunnel.mtu as the lwIP read buffer size.")
    }

    func testMtuIsClamped() {
        let tooSmall = EngineConfigBuilder.build(mtu: 100, isIPv6Enabled: false, localPort: 10808)
        XCTAssertTrue(tooSmall.contains("mtu: 1280"))
        let tooLarge = EngineConfigBuilder.build(mtu: 30000, isIPv6Enabled: false, localPort: 10808)
        XCTAssertTrue(tooLarge.contains("mtu: 9000"))
    }

    func testMapdnsSectionPresent() {
        let config = EngineConfigBuilder.build(mtu: 1500, isIPv6Enabled: false, localPort: 10808)
        XCTAssertTrue(config.contains("mapdns:"))
        XCTAssertTrue(config.contains("network: 100.64.0.0"))
        XCTAssertTrue(config.contains("netmask: 255.192.0.0"))
        XCTAssertTrue(config.contains("cache-size: 10000"))
    }

    func testDefaultTuningBoundsSessionMemory() {
        let config = EngineConfigBuilder.build(mtu: 1500, isIPv6Enabled: false, localPort: 10808)
        XCTAssertTrue(config.contains("task-stack-size: \(defaultTuning.effectiveTaskStackSize)"))
        XCTAssertTrue(config.contains("tcp-buffer-size: 16384"))
        XCTAssertTrue(config.contains("udp-copy-buffer-nums: 2"))
        XCTAssertTrue(config.contains("max-session-count: 256"))
        XCTAssertTrue(config.contains("connect-timeout: 5000"))
        XCTAssertTrue(config.contains("read-write-timeout: 60000"))
    }

    func testEffectiveStackSizeEnforcesEngineFloor() {
        // Floor = 20480 + max(16384, 1500*2) = 36864.
        XCTAssertEqual(defaultTuning.effectiveTaskStackSize, 36864)

        // Large TCP buffers raise the floor.
        var tuning = EngineConfigBuilder.Tuning()
        tuning.tcpBufferSize = 65536
        XCTAssertEqual(tuning.effectiveTaskStackSize, 20480 + 65536)

        // A requested stack above the floor is honored.
        var bigStack = EngineConfigBuilder.Tuning()
        bigStack.taskStackSize = 131072
        XCTAssertEqual(bigStack.effectiveTaskStackSize, 131072)
    }

    func testCustomTuningIsRendered() {
        var tuning = EngineConfigBuilder.Tuning()
        tuning.maxSessionCount = 128
        tuning.connectTimeoutMs = 10000
        tuning.logLevel = "debug"
        let config = EngineConfigBuilder.build(mtu: 1500, isIPv6Enabled: false, localPort: 10808, tuning: tuning)
        XCTAssertTrue(config.contains("max-session-count: 128"))
        XCTAssertTrue(config.contains("connect-timeout: 10000"))
        XCTAssertTrue(config.contains("log-level: debug"))
    }

    func testIPv6FlagHasNoEffectOnConfig() {
        let without = EngineConfigBuilder.build(mtu: 1500, isIPv6Enabled: false, localPort: 10808)
        let with = EngineConfigBuilder.build(mtu: 1500, isIPv6Enabled: true, localPort: 10808)
        XCTAssertEqual(without, with, "IPv6 routing is configured via NEPacketTunnelNetworkSettings, not the engine YAML.")
    }
}