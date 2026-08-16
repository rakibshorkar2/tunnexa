import XCTest
@testable import Tunnexa

/// Verifies the staged SOCKS5 health probe against an in-process mock server
/// (no external network required).
final class HealthTesterTests: XCTestCase {

    override func tearDown() {
        ProxyHealthTester.testTimeout = 5.0
        super.tearDown()
    }

    func testOnlineProxyReportsSuccessAndLatency() {
        let mock = MockSocksServer(behavior: .online)
        mock.startOrFail(self)
        defer { mock.stop() }

        let proxy = SOCKS5Proxy(name: "Mock", host: "127.0.0.1", port: Int(mock.port))
        let expectation = XCTestExpectation(description: "online result")

        ProxyHealthTester.testLatency(proxy: proxy) { result in
            XCTAssertEqual(result.status, .online)
            XCTAssertNil(result.failureStage)
            XCTAssertNotNil(result.totalLatencyMs)
            XCTAssertGreaterThanOrEqual(result.totalLatencyMs ?? 0, 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
    }

    func testAuthRequiredProxyAuthenticatesAndSucceeds() {
        let mock = MockSocksServer(behavior: .authRequired)
        mock.startOrFail(self)
        defer { mock.stop() }

        let proxy = SOCKS5Proxy(name: "Mock", host: "127.0.0.1", port: Int(mock.port), username: "healthuser")
        let expectation = XCTestExpectation(description: "auth result")

        ProxyHealthTester.testLatency(proxy: proxy, password: "healthpass") { result in
            XCTAssertEqual(result.status, .online, "Proxy requiring auth must authenticate and succeed")
            XCTAssertEqual(mock.lastAuthUsername, "healthuser")
            XCTAssertEqual(mock.lastAuthPassword, "healthpass")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
    }

    func testAuthRejectedProxyReportsAuthFailed() {
        let mock = MockSocksServer(behavior: .authRejected)
        mock.startOrFail(self)
        defer { mock.stop() }

        let proxy = SOCKS5Proxy(name: "Mock", host: "127.0.0.1", port: Int(mock.port), username: "baduser")
        let expectation = XCTestExpectation(description: "auth failure")

        ProxyHealthTester.testLatency(proxy: proxy, password: "badpass") { result in
            XCTAssertEqual(result.status, .authFailed)
            XCTAssertEqual(result.failureStage, .auth)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
    }

    func testConnectRejectedProxyReportsConnFailed() {
        let mock = MockSocksServer(behavior: .connectRejected)
        mock.startOrFail(self)
        defer { mock.stop() }

        let proxy = SOCKS5Proxy(name: "Mock", host: "127.0.0.1", port: Int(mock.port))
        let expectation = XCTestExpectation(description: "connect rejection")

        ProxyHealthTester.testLatency(proxy: proxy) { result in
            XCTAssertEqual(result.status, .connFailed)
            XCTAssertEqual(result.failureStage, .connectCommand)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
    }

    func testSilentServerTimesOut() {
        ProxyHealthTester.testTimeout = 1.0
        let mock = MockSocksServer(behavior: .silent)
        mock.startOrFail(self)
        defer { mock.stop() }

        let proxy = SOCKS5Proxy(name: "Mock", host: "127.0.0.1", port: Int(mock.port))
        let expectation = XCTestExpectation(description: "timeout")

        ProxyHealthTester.testLatency(proxy: proxy) { result in
            XCTAssertEqual(result.status, .timeout)
            XCTAssertEqual(result.failureStage, .connect)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
    }

    func testConnectionRefusedReportsConnFailed() {
        // Bind and release a port so nothing is listening there.
        let deadPort = allocateLoopbackPort()

        let proxy = SOCKS5Proxy(name: "Dead", host: "127.0.0.1", port: Int(deadPort))
        let expectation = XCTestExpectation(description: "refused")

        ProxyHealthTester.testLatency(proxy: proxy) { result in
            XCTAssertEqual(result.status, .connFailed)
            XCTAssertEqual(result.failureStage, .connect)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
    }

    func testCompletionFiresExactlyOnce() {
        let mock = MockSocksServer(behavior: .online)
        mock.startOrFail(self)
        defer { mock.stop() }

        let proxy = SOCKS5Proxy(name: "Mock", host: "127.0.0.1", port: Int(mock.port))
        var completionCount = 0
        let expectation = XCTestExpectation(description: "exactly once")

        ProxyHealthTester.testLatency(proxy: proxy) { _ in
            completionCount += 1
            if completionCount == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    XCTAssertEqual(completionCount, 1, "Completion must fire exactly once")
                    expectation.fulfill()
                }
            }
        }
        wait(for: [expectation], timeout: 10)
    }
}