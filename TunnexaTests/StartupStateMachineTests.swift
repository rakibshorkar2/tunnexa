import XCTest
@testable import Tunnexa

/// Hermetic tests for the per-session startup state machine.
///
/// The critical regression this guards: iOS reuses the provider instance
/// across sessions, so a `.succeeded`/`.failed` state from a previous session
/// must never block the next session's completion handler.
final class StartupStateMachineTests: XCTestCase {

    func testSettleInvokesHandlerExactlyOnce() {
        let machine = StartupStateMachine()
        let handler = { (_: Error?) in }
        machine.begin(handler: handler)

        XCTAssertEqual(machine.currentState, .inProgress)
        XCTAssertTrue(machine.isInProgress)

        let first = machine.settle(nil)
        XCTAssertNotNil(first, "first settle must return the handler")
        XCTAssertEqual(machine.currentState, .succeeded)
        XCTAssertFalse(machine.isInProgress)

        let second = machine.settle(nil)
        XCTAssertNil(second, "second settle must return nil: handler already invoked")
        let third = machine.settle(NSError(domain: "test", code: 1))
        XCTAssertNil(third, "settle after success must be ignored")
    }

    func testSettleFailureFlipsStateToFailed() {
        let machine = StartupStateMachine()
        machine.begin(handler: { _ in })
        let error = NSError(domain: "test", code: 1)
        XCTAssertNotNil(machine.settle(error))
        XCTAssertEqual(machine.currentState, .failed)
    }

    func testBeginResetsPreviousSession() {
        let machine = StartupStateMachine()
        machine.begin(handler: { _ in })
        _ = machine.settle(nil)
        XCTAssertEqual(machine.currentState, .succeeded)

        // A new startTunnel call on the same (reused) provider instance.
        var invoked = false
        machine.begin(handler: { _ in invoked = true })
        XCTAssertEqual(machine.currentState, .inProgress)
        XCTAssertTrue(machine.isInProgress)
        XCTAssertFalse(invoked, "stale handler from the previous session must not be invoked")

        machine.settle(nil)?(nil)
        XCTAssertTrue(invoked)
    }

    func testBeginAfterFailedSessionAlsoResets() {
        let machine = StartupStateMachine()
        machine.begin(handler: { _ in })
        _ = machine.settle(NSError(domain: "test", code: 7))
        XCTAssertEqual(machine.currentState, .failed)

        var invoked = false
        machine.begin(handler: { _ in invoked = true })
        XCTAssertEqual(machine.currentState, .inProgress)
        machine.settle(nil)?(nil)
        XCTAssertTrue(invoked)
    }

    func testCancelRetiresPendingHandlerWithoutInvokingIt() {
        let machine = StartupStateMachine()
        var invoked = false
        machine.begin(handler: { _ in invoked = true })

        machine.cancel()
        XCTAssertEqual(machine.currentState, .failed)
        XCTAssertFalse(invoked, "cancel is used on tunnel stop: the handler must never be invoked")
        XCTAssertNil(machine.settle(nil), "settle after cancel must not resurrect a handler")
        XCTAssertFalse(invoked)
    }

    func testBeginAfterCancelStartsFreshSession() {
        let machine = StartupStateMachine()
        machine.begin(handler: { _ in })
        machine.cancel()
        XCTAssertEqual(machine.currentState, .failed)

        var invoked = false
        machine.begin(handler: { _ in invoked = true })
        XCTAssertTrue(machine.isInProgress)
        machine.settle(nil)?(nil)
        XCTAssertTrue(invoked)
    }

    func testSettleBeforeBeginReturnsNil() {
        let machine = StartupStateMachine()
        XCTAssertNil(machine.settle(nil))
    }
}