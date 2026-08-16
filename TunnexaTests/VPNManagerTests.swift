import XCTest
import Darwin
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
        XCTAssertTrue(details.userFriendlyExplanation.contains("not a SOCKS5 server or proxy configuration error"),
                      "LiveContainer error must explicitly rule out SOCKS5 configuration blame")
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

// MARK: - ProxyEndpointResolver deadlock regression
//
// Regression for the serial-queue deadlock: the async variant used to
// dispatch onto the SAME serial queue as the synchronous variant and then
// block on a semaphore for its result — the inner block could never run, so
// every domain resolution stalled for the full 3 s timeout. The queue is now
// concurrent; these tests assert wall-clock behaviour, which the serial
// implementation fails catastrophically.
final class ProxyEndpointResolverTests: XCTestCase {

    func testConcurrentAsyncResolvesCompleteQuickly() {
        let resolver = ProxyEndpointResolver.shared
        resolver.clearCache()

        let expectation = expectation(description: "all async resolves completed")
        let lock = NSLock()
        var completed = 0
        let total = 4

        let start = Date()
        for _ in 0..<total {
            resolver.resolve(host: "example.invalid") { _ in
                lock.lock()
                completed += 1
                let done = completed == total
                lock.unlock()
                if done {
                    expectation.fulfill()
                }
            }
        }

        wait(for: [expectation], timeout: 10)
        let elapsed = Date().timeIntervalSince(start)
        // The serial implementation takes ~3 s per call (semaphore timeout),
        // serialized -> 12 s for 4 calls. The concurrent implementation must
        // finish in well under half of one stall.
        XCTAssertLessThan(elapsed, 2.5, "async resolves must not stall on a serial queue (took \(elapsed)s)")
    }

    func testSyncAndAsyncMixedUsageDoesNotDeadlock() {
        let resolver = ProxyEndpointResolver.shared
        resolver.clearCache()

        let expectation = expectation(description: "async resolve completed")
        var asyncDone = false

        // Fire the async resolve first, then a sync resolve on the calling
        // thread: the sync resolve must return promptly even while the async
        // one is in flight.
        resolver.resolve(host: "example.invalid") { _ in
            asyncDone = true
            expectation.fulfill()
        }

        let start = Date()
        _ = resolver.resolve(host: "example.invalid", timeout: 3.0)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.5, "sync resolve must not wait out its timeout behind a queued async resolve (took \(elapsed)s)")

        wait(for: [expectation], timeout: 10)
        XCTAssertTrue(asyncDone)
    }

    func testIPLiteralsResolveSynchronouslyWithoutNetwork() {
        let resolver = ProxyEndpointResolver.shared
        XCTAssertEqual(resolver.resolve(host: "192.0.2.1"), ["192.0.2.1"])
        XCTAssertEqual(resolver.resolve(host: "2001:db8::1"), ["2001:db8::1"])
        XCTAssertEqual(resolver.resolve(host: ""), [])
    }
}

// MARK: - TunnelError mapping

final class TunnelErrorTests: XCTestCase {

    func testProviderCodeMapping() {
        XCTAssertEqual(TunnelError.provider(code: 100, message: "x"), .invalidConfiguration)
        XCTAssertEqual(TunnelError.provider(code: 101, message: "x"), .invalidConfiguration)
        XCTAssertEqual(TunnelError.provider(code: 102, message: "x"), .invalidConfiguration)
        XCTAssertEqual(TunnelError.provider(code: 3, message: "x"), .tunSetupFailed(detail: "x"))
        XCTAssertEqual(TunnelError.provider(code: 4, message: "x"), .unknown(code: 4, detail: "x"))
        XCTAssertEqual(TunnelError.provider(code: 5, message: "x"), .probeFailed(detail: "x"))
        XCTAssertEqual(TunnelError.provider(code: 6, message: "x"), .proxyUnavailable(detail: "x"))
        XCTAssertEqual(TunnelError.provider(code: 7, message: "x"), .resourceLimit(detail: "x"))
        XCTAssertEqual(TunnelError.provider(code: 99, message: "y"), .unknown(code: 99, detail: "y"))
    }

    func testAsNSErrorPreservesCodes() {
        let nsError = TunnelError.engineExited(code: 42).asNSError(domain: "Tunnexa.Provider")
        XCTAssertEqual(nsError.domain, "Tunnexa.Provider")
        XCTAssertEqual(nsError.code, 4)
        XCTAssertEqual(nsError.userInfo["TunnexaEngineExitCode"] as? NSNumber, NSNumber(value: 42))
        XCTAssertNotNil(nsError.userInfo[NSLocalizedDescriptionKey])

        let nativeError = TunnelError.nativeInitializationFailed(code: 1, detail: "boom").asNSError()
        XCTAssertEqual(nativeError.code, 1)
        XCTAssertEqual(nativeError.userInfo["TunnexaNativeErrorCode"] as? NSNumber, NSNumber(value: 1))
    }

    func testPOSIXDescriptions() {
        XCTAssertEqual(POSIXErrorDiagnostics.describe(errno: EMFILE), "EMFILE: Too many open files")
        XCTAssertEqual(POSIXErrorDiagnostics.describe(errno: EADDRINUSE), "EADDRINUSE: Address already in use")
        XCTAssertNil(POSIXErrorDiagnostics.describe(errno: 9999))
    }
}
