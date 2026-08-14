import XCTest
@testable import Tunnexa

final class AutoReconnectTests: XCTestCase {

    func testBackoffDelayLadder() {
        XCTAssertEqual(AutoReconnectPolicy.delay(forAttempt: 0), 0, "Attempt 0 must wait nothing")
        XCTAssertEqual(AutoReconnectPolicy.delay(forAttempt: 1), 1)
        XCTAssertEqual(AutoReconnectPolicy.delay(forAttempt: 2), 2)
        XCTAssertEqual(AutoReconnectPolicy.delay(forAttempt: 3), 4)
        XCTAssertEqual(AutoReconnectPolicy.delay(forAttempt: 4), 8)
        XCTAssertEqual(AutoReconnectPolicy.delay(forAttempt: 5), 15)
        XCTAssertEqual(AutoReconnectPolicy.delay(forAttempt: 6), 30)
    }

    func testBackoffClampsAtFinalValue() {
        XCTAssertEqual(AutoReconnectPolicy.delay(forAttempt: 7), 30, "Beyond the ladder the final value must be used")
        XCTAssertEqual(AutoReconnectPolicy.delay(forAttempt: 100), 30)
        XCTAssertEqual(AutoReconnectPolicy.delay(forAttempt: -3), 0, "Invalid attempts must be treated as zero")
    }

    func testRetryCap() {
        XCTAssertTrue(AutoReconnectPolicy.mayRetry(afterAttempt: 0))
        XCTAssertTrue(AutoReconnectPolicy.mayRetry(afterAttempt: 1))
        XCTAssertTrue(AutoReconnectPolicy.mayRetry(afterAttempt: 4))
        XCTAssertFalse(AutoReconnectPolicy.mayRetry(afterAttempt: 5), "Must stop after maxAttempts")
        XCTAssertFalse(AutoReconnectPolicy.mayRetry(afterAttempt: 6))
    }

    func testLadderMatchesSpec() {
        XCTAssertEqual(AutoReconnectPolicy.backoffDelays, [1, 2, 4, 8, 15, 30])
        XCTAssertEqual(AutoReconnectPolicy.maxAttempts, 5)
    }

    func testDelayMonotonicNonDecreasing() {
        var previous: TimeInterval = -1
        for attempt in 1...AutoReconnectPolicy.backoffDelays.count {
            let delay = AutoReconnectPolicy.delay(forAttempt: attempt)
            XCTAssertGreaterThanOrEqual(delay, previous)
            previous = delay
        }
    }
}