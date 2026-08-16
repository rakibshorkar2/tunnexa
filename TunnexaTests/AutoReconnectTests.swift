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

    func testJitteredDelayBounds() {
        // random = 0.0 -> base * (1 - fraction); random = 1.0 -> base.
        let lower = AutoReconnectPolicy.jitteredDelay(forAttempt: 3, jitterFraction: 0.25, random: { 0.0 })
        let upper = AutoReconnectPolicy.jitteredDelay(forAttempt: 3, jitterFraction: 0.25, random: { 1.0 })
        XCTAssertEqual(upper, 4.0, "random = 1.0 must return the base delay")
        XCTAssertEqual(lower, 3.0, "random = 0.0 must return base * (1 - fraction)")
    }

    func testJitteredDelayNeverExceedsBase() {
        for attempt in 1...AutoReconnectPolicy.backoffDelays.count {
            let delay = AutoReconnectPolicy.jitteredDelay(forAttempt: attempt, jitterFraction: 0.5, random: { 1.0 })
            XCTAssertEqual(delay, AutoReconnectPolicy.delay(forAttempt: attempt))
        }
    }

    func testJitteredDelayClampsFraction() {
        // A hostile fraction (> 0.5) must be clamped, never negative delays.
        for random in [0.0, 0.5, 1.0] {
            let delay = AutoReconnectPolicy.jitteredDelay(forAttempt: 4, jitterFraction: 2.0, random: { random })
            XCTAssertGreaterThanOrEqual(delay, 0.0)
            XCTAssertLessThanOrEqual(delay, 8.0)
        }
    }

    func testJitteredDelayRespectsRandomRange() {
        for _ in 0..<50 {
            let delay = AutoReconnectPolicy.jitteredDelay(forAttempt: 5, jitterFraction: 0.25, random: { Double.random(in: 0..<1) })
            // delay(forAttempt: 5) = 15 (ladder index 4).
            XCTAssertGreaterThanOrEqual(delay, 15.0 * 0.75)
            XCTAssertLessThanOrEqual(delay, 15.0)
        }
    }
}