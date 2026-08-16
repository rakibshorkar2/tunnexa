import XCTest
@testable import Tunnexa

/// Hermetic tests for runtime environment detection and capabilities.
///
/// `isSimulator: false` is injected so the device branches are exercised even
/// though the test bundle runs on the simulator.
final class EnvironmentDetectorTests: XCTestCase {

    private let simulator = false

    // MARK: - LiveContainer detection

    func testLiveContainerDetectedViaLCAppIdEnvVar() {
        XCTAssertEqual(
            VPNEnvironmentDetector.detectEnvironment(
                environment: ["LC_APP_ID": "com.some.guest"],
                bundleIdentifier: "com.rakib.tunnexa",
                isSimulator: simulator
            ),
            .liveContainer
        )
    }

    func testLiveContainerDetectedViaLiveContainerEnvVar() {
        XCTAssertEqual(
            VPNEnvironmentDetector.detectEnvironment(
                environment: ["LIVE_CONTAINER": "1"],
                bundleIdentifier: "com.rakib.tunnexa",
                isSimulator: simulator
            ),
            .liveContainer
        )
    }

    func testLiveContainerDetectedViaLCEndContainerEnvVar() {
        XCTAssertEqual(
            VPNEnvironmentDetector.detectEnvironment(
                environment: ["LIVECONTAINER": "1"],
                bundleIdentifier: "com.rakib.tunnexa",
                isSimulator: simulator
            ),
            .liveContainer
        )
    }

    func testLiveContainerDetectedViaLCBundleIdEnvVar() {
        XCTAssertEqual(
            VPNEnvironmentDetector.detectEnvironment(
                environment: ["LC_BUNDLE_ID": "com.some.guest"],
                bundleIdentifier: "com.rakib.tunnexa",
                isSimulator: simulator
            ),
            .liveContainer
        )
    }

    func testLiveContainerDetectedViaBundlePathSignature() {
        XCTAssertEqual(
            VPNEnvironmentDetector.detectEnvironment(
                bundlePath: "/var/mobile/Containers/Bundle/Application/LiveContainer/Apps/com.kdt.livecontainer/example.app",
                bundleIdentifier: "com.rakib.tunnexa",
                isSimulator: simulator
            ),
            .liveContainer
        )
    }

    func testLiveContainerDetectedViaDocumentsPathSignature() {
        XCTAssertEqual(
            VPNEnvironmentDetector.detectEnvironment(
                environment: [:],
                bundleIdentifier: "com.rakib.tunnexa",
                documentsPath: "/var/mobile/Containers/Data/Application/XXXX/Documents/com.kdt.livecontainer/Apps",
                isSimulator: simulator
            ),
            .liveContainer
        )
    }

    func testLiveContainerDetectedViaBundleIdentifier() {
        XCTAssertEqual(
            VPNEnvironmentDetector.detectEnvironment(
                environment: [:],
                bundleIdentifier: "com.kdt.livecontainer.host",
                isSimulator: simulator
            ),
            .liveContainer
        )
    }

    // MARK: - Standalone / unknown / simulator

    func testStandaloneDetectedWhenNothingSuspiciousPresent() {
        XCTAssertEqual(
            VPNEnvironmentDetector.detectEnvironment(
                environment: [:],
                bundlePath: "/var/mobile/Containers/Bundle/Application/ABCD-EFGH/tunnexa.app",
                bundleIdentifier: "com.rakib.tunnexa",
                documentsPath: "/var/mobile/Containers/Data/Application/ABCD-EFGH/Documents",
                isSimulator: simulator
            ),
            .standalone
        )
    }

    func testUnknownForUnrecognizedBundleIdentifier() {
        XCTAssertEqual(
            VPNEnvironmentDetector.detectEnvironment(
                environment: [:],
                bundleIdentifier: "com.someone.else",
                isSimulator: simulator
            ),
            .unknown
        )
    }

    func testLiveContainerSignatureWinsOverBundleId() {
        XCTAssertEqual(
            VPNEnvironmentDetector.detectEnvironment(
                environment: ["LC_APP_ID": "com.rakib.tunnexa"],
                bundleIdentifier: "com.rakib.tunnexa",
                isSimulator: simulator
            ),
            .liveContainer,
            "A LiveContainer signature must win even when the bundle id matches the standalone id"
        )
    }

    func testSimulatorReportedWhenFlagSet() {
        XCTAssertEqual(
            VPNEnvironmentDetector.detectEnvironment(
                environment: [:],
                bundleIdentifier: "com.rakib.tunnexa",
                isSimulator: true
            ),
            .simulator
        )
    }

    // MARK: - Support gating

    func testOnlyStandaloneIsSupportedForSystemVPN() {
        XCTAssertTrue(VPNRuntimeEnvironment.standalone.isSupportedForSystemVPN)
        XCTAssertFalse(VPNRuntimeEnvironment.liveContainer.isSupportedForSystemVPN)
        XCTAssertFalse(VPNRuntimeEnvironment.simulator.isSupportedForSystemVPN)
        XCTAssertFalse(VPNRuntimeEnvironment.unsupported.isSupportedForSystemVPN)
        XCTAssertFalse(VPNRuntimeEnvironment.unknown.isSupportedForSystemVPN)
    }

    // MARK: - Capabilities

    func testStandaloneCapabilities() {
        let caps = VPNEnvironmentDetector.capabilities(for: .standalone)
        XCTAssertTrue(caps.canUsePacketTunnel)
        XCTAssertFalse(caps.canUseInAppProxy)
        XCTAssertTrue(caps.canUseSharedAppGroup)
    }

    func testLiveContainerCapabilities() {
        let caps = VPNEnvironmentDetector.capabilities(for: .liveContainer)
        XCTAssertFalse(caps.canUsePacketTunnel)
        XCTAssertTrue(caps.canUseInAppProxy)
        XCTAssertFalse(caps.canUseSharedAppGroup)
    }

    func testSimulatorCapabilities() {
        let caps = VPNEnvironmentDetector.capabilities(for: .simulator)
        XCTAssertFalse(caps.canUsePacketTunnel)
        XCTAssertTrue(caps.canUseInAppProxy)
        XCTAssertTrue(caps.canUseSharedAppGroup)
    }

    func testUnknownAndUnsupportedCapabilitiesAreNone() {
        XCTAssertEqual(VPNEnvironmentDetector.capabilities(for: .unknown), .none)
        XCTAssertEqual(VPNEnvironmentDetector.capabilities(for: .unsupported), .none)
    }
}