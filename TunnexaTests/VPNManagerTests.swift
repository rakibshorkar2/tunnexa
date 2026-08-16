import XCTest
@testable import Tunnexa

/// Tests for VPNEnvironmentDetector classification logic.
final class VPNManagerTests: XCTestCase {
    
    // MARK: - Environment Detection Tests
    
    func testDetectStandaloneByBundleIdentifier() {
        let env = VPNEnvironmentDetector.detectEnvironment(
            environment: [:],
            bundlePath: "/private/var/containers/Bundle/Application/ABCD1234/Tunnexa.app",
            bundleIdentifier: "com.rakib.tunnexa",
            documentsPath: "/var/mobile/Containers/Data/Application/XYZ/Documents",
            isSimulator: false
        )
        XCTAssertEqual(env, .standalone, "Canonical Tunnexa bundle ID should be classified as standalone")
        XCTAssertTrue(env.isSupportedForSystemVPN)
    }
    
    func testDetectLiveContainerByEnvironmentVariable() {
        let env = VPNEnvironmentDetector.detectEnvironment(
            environment: ["LC_APP_ID": "com.rakib.tunnexa"],
            bundlePath: "/private/var/containers/Bundle/Application/ABCD1234/Tunnexa.app",
            bundleIdentifier: "com.rakib.tunnexa",
            documentsPath: "/var/mobile/Containers/Data/Application/XYZ/Documents",
            isSimulator: false
        )
        XCTAssertEqual(env, .liveContainer, "LC_APP_ID env var must classify as LiveContainer")
        XCTAssertFalse(env.isSupportedForSystemVPN)
    }
    
    func testDetectLiveContainerByBundlePath() {
        let env = VPNEnvironmentDetector.detectEnvironment(
            environment: [:],
            bundlePath: "/private/var/containers/Bundle/Application/ABCD1234/LiveContainer/Tunnexa.app",
            bundleIdentifier: "com.rakib.tunnexa",
            documentsPath: "/var/mobile/Containers/Data/Application/XYZ/Documents",
            isSimulator: false
        )
        XCTAssertEqual(env, .liveContainer, "LiveContainer directory in bundle path must be detected")
        XCTAssertFalse(env.isSupportedForSystemVPN)
    }
    
    func testDetectLiveContainerByDocumentsPath() {
        let env = VPNEnvironmentDetector.detectEnvironment(
            environment: [:],
            bundlePath: "/private/var/containers/Bundle/Application/ABCD1234/Tunnexa.app",
            bundleIdentifier: "com.rakib.tunnexa",
            documentsPath: "/var/mobile/Containers/Data/Application/XYZ/LiveContainer/Documents",
            isSimulator: false
        )
        XCTAssertEqual(env, .liveContainer, "LiveContainer in documents path must be detected")
    }
    
    func testDetectUnknownForUnrecognizedBundle() {
        let env = VPNEnvironmentDetector.detectEnvironment(
            environment: [:],
            bundlePath: "/private/var/containers/Bundle/Application/ABCD1234/SomeOtherApp.app",
            bundleIdentifier: "com.unknown.app",
            documentsPath: "/var/mobile/Containers/Data/Application/XYZ/Documents",
            isSimulator: false
        )
        XCTAssertEqual(env, .unknown, "Unrecognized bundle should return .unknown (not falsely liveContainer)")
        XCTAssertFalse(env.isSupportedForSystemVPN, "Fail-safe: .unknown must NOT start a system VPN")
    }
    
    func testNoFalsePositiveLiveContainerDetection() {
        let env = VPNEnvironmentDetector.detectEnvironment(
            environment: [:],
            bundlePath: "/private/var/containers/Bundle/Application/ABCD1234/Tunnexa.app",
            bundleIdentifier: "com.rakib.tunnexa",
            documentsPath: nil,
            isSimulator: false
        )
        XCTAssertNotEqual(env, .liveContainer, "Must not falsely classify standalone as LiveContainer")
    }
    
    func testSimulatorEnvironmentIsNotSupportedForSystemVPN() {
        let env = VPNEnvironmentDetector.detectEnvironment(
            environment: [:],
            bundleIdentifier: "com.rakib.tunnexa",
            isSimulator: true
        )
        XCTAssertEqual(env, .simulator)
        XCTAssertFalse(env.isSupportedForSystemVPN)
        XCTAssertTrue(VPNEnvironmentDetector.capabilities(for: env).canUseInAppProxy)
    }
    
    // MARK: - VPNErrorDetails Tests
    
    func testErrorDetailsFromNSError() {
        let underlying = NSError(domain: "NEVPNErrorDomain", code: 5, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        let error = NSError(domain: "NEVPNErrorDomain", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "Failed to save preferences",
            NSUnderlyingErrorKey: underlying
        ])
        let details = VPNErrorDetails(error: error, environment: .standalone)
        XCTAssertEqual(details.domain, "NEVPNErrorDomain")
        XCTAssertEqual(details.code, 5)
        XCTAssertEqual(details.underlyingDomain, "NEVPNErrorDomain")
        XCTAssertEqual(details.underlyingCode, 5)
        XCTAssertFalse(details.userFriendlyExplanation.isEmpty)
    }
    
    func testErrorDetailForLiveContainerEnvironment() {
        let details = VPNErrorDetails(
            domain: "Tunnexa.Environment",
            code: 100,
            message: "LiveContainer guest runtime",
            environment: .liveContainer
        )
        XCTAssertEqual(details.environment, .liveContainer)
        XCTAssertTrue(details.userFriendlyExplanation.contains("LiveContainer"))
        XCTAssertTrue(details.userFriendlyExplanation.contains("standalone"))
        XCTAssertFalse(details.userFriendlyExplanation.contains("SOCKS5 server"), "LiveContainer error must not blame SOCKS5 configuration")
    }
    
    func testErrorDetailsForPermissionDenied() {
        let error = NSError(domain: "NEVPNErrorDomain", code: 5, userInfo: [NSLocalizedDescriptionKey: "Permission denied by system"])
        let details = VPNErrorDetails(error: error, environment: .standalone)
        let explanation = details.userFriendlyExplanation
        XCTAssertFalse(explanation.isEmpty)
        XCTAssertTrue(explanation.contains("entitlement") || explanation.contains("Permission") || explanation.contains("provisioning"))
    }
    
    func testVPNManagerTargetBundleIdentifier() {
        XCTAssertEqual(
            VPNManager.targetProviderBundleIdentifier,
            "com.rakib.tunnexa.PacketTunnel",
            "Provider bundle ID must match the embedded extension's CFBundleIdentifier"
        )
    }
}
