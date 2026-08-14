import XCTest
@testable import Tunnexa

/// Every log message and persisted error description passes through
/// `SharedLogging.redactCredentials`. These tests pin the redaction contract.
final class LogRedactionTests: XCTestCase {

    func testRedactsPasswordEqualsForm() {
        let redacted = SharedLogging.redactCredentials("config password=hunter2")
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertTrue(redacted.contains("password: [REDACTED]"))
    }

    func testRedactsPasswordColonForm() {
        let redacted = SharedLogging.redactCredentials("password: hunter2")
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertTrue(redacted.contains("password: [REDACTED]"))
    }

    func testRedactsQuotedJSONCredentials() {
        let input = #"{"proxy": {"username": "alice", "password": "s3cret"}}"#
        let redacted = SharedLogging.redactCredentials(input)
        XCTAssertFalse(redacted.contains("alice"))
        XCTAssertFalse(redacted.contains("s3cret"))
        XCTAssertTrue(redacted.contains("[REDACTED]"))
    }

    func testRedactsURLUserInfo() {
        let redacted = SharedLogging.redactCredentials("socks5://user:pw@host.example:1080")
        XCTAssertFalse(redacted.contains("user:pw"))
        XCTAssertFalse(redacted.contains("pw@"))
        XCTAssertTrue(redacted.contains("socks5://[REDACTED]@host.example:1080"))
    }

    func testRedactsAuthTokensAndClientSecrets() {
        let redacted = SharedLogging.redactCredentials("auth_token=abcdef12345 client_secret=xyz")
        XCTAssertFalse(redacted.contains("abcdef12345"))
        XCTAssertFalse(redacted.contains("xyz"))
        XCTAssertTrue(redacted.contains("auth_token: [REDACTED]"))
        XCTAssertTrue(redacted.contains("client_secret: [REDACTED]"))
    }

    func testRedactsUsernameEqualsForm() {
        let redacted = SharedLogging.redactCredentials("username=alice")
        XCTAssertFalse(redacted.contains("alice"))
        XCTAssertTrue(redacted.contains("username: [REDACTED]"))
    }

    func testRedactsSingleQuotedValues() {
        let redacted = SharedLogging.redactCredentials("password: 'secret-value'")
        XCTAssertFalse(redacted.contains("secret-value"))
        XCTAssertTrue(redacted.contains("password: [REDACTED]"))
    }

    func testLeavesOrdinaryMessagesUntouched() {
        let message = "Tunnel started on fd 3 with MTU 9000"
        XCTAssertEqual(SharedLogging.redactCredentials(message), message)
    }

    func testRedactionIsIdempotent() {
        let input = "password=abc123"
        let once = SharedLogging.redactCredentials(input)
        let twice = SharedLogging.redactCredentials(once)
        XCTAssertEqual(once, twice)
        XCTAssertFalse(twice.contains("abc123"))
    }

    func testLoggedMessagesNeverContainCredentials() {
        SharedLogging.clearLogs()
        SharedLogging.log("Connection attempt with password=supersecret", category: .vpn, level: .error)

        let expectation = XCTestExpectation(description: "log flushed and redacted")
        // Logging is async (file writes on a serial queue); poll briefly.
        var attempts = 0
        func poll() {
            attempts += 1
            let logs = SharedLogging.readLogs()
            if logs.contains("supersecret") {
                XCTFail("Credentials leaked into the log file: \(logs)")
                expectation.fulfill()
                return
            }
            if logs.contains("password: [REDACTED]") {
                expectation.fulfill()
                return
            }
            if attempts > 50 {
                XCTFail("Log never flushed")
                expectation.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
        }
        poll()
        wait(for: [expectation], timeout: 10)
        SharedLogging.clearLogs()
    }

    func testVPNErrorDetailsRedactErrorMessages() {
        let error = NSError(domain: "Tunnexa", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Auth failed password=hunter2",
            NSLocalizedFailureReasonErrorKey: "password: hunter2"
        ])
        let details = VPNErrorDetails(error: error, environment: .standalone)
        XCTAssertFalse(details.message.contains("hunter2"))
        XCTAssertFalse(details.failureReason?.contains("hunter2") ?? false)
        XCTAssertTrue(details.message.contains("password: [REDACTED]"))
    }
}