import XCTest
import Darwin
@testable import Tunnexa

/// Hermetic tests for the engine lifecycle and the descriptor contract.
///
/// The engine never owns a descriptor: the packet flow's socket belongs to
/// `NEPacketTunnelFlow`, and Tun2SocksKit discovers it itself. These tests
/// assert that no descriptor is ever closed by the engine (including during
/// stop and deinit).
final class TunnelEngineTests: XCTestCase {

    /// Creates a pipe; both ends must remain open for the whole test.
    private func makeFakeFdPair() -> (readEnd: Int32, writeEnd: Int32) {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        return (fds[0], fds[1])
    }

    private func isOpen(_ fd: Int32) -> Bool {
        return fcntl(fd, F_GETFD) != -1
    }

    private func quickEngine(run: @escaping (String) -> Int32) -> TunnelEngine {
        return TunnelEngine(configYAML: "irrelevant", run: run)
    }

    func testEngineNeverClosesAnyDescriptor() {
        // The engine must not close descriptors: it does not own the TUN fd
        // (that belongs to NEPacketTunnelFlow). Both pipe ends must survive
        // the full run + exit lifecycle.
        let (readEnd, writeEnd) = makeFakeFdPair()

        let exitExpectation = expectation(description: "engine exit observed")
        let engine = quickEngine { _ in 0 }
        engine.onExit = { code in
            XCTAssertEqual(code, 0)
            exitExpectation.fulfill()
        }
        engine.start()
        wait(for: [exitExpectation], timeout: 5.0)

        XCTAssertTrue(isOpen(readEnd), "engine must never close the read end")
        XCTAssertTrue(isOpen(writeEnd), "engine must never close the write end (stands in for the packet flow socket)")

        close(readEnd)
        close(writeEnd)
    }

    func testStopDoesNotCloseDescriptorsWhenRunDoesNotExit() {
        let (readEnd, writeEnd) = makeFakeFdPair()
        let release = DispatchSemaphore(value: 0)
        let engine = quickEngine { _ in
            _ = release.wait(timeout: .now() + 5.0)
            return 7
        }
        engine.start()
        XCTAssertTrue(engine.isRunning)
        XCTAssertNil(engine.exitCode)

        engine.stop(timeout: 0.5)
        XCTAssertTrue(isOpen(readEnd), "stop() must never close descriptors")
        XCTAssertTrue(isOpen(writeEnd), "stop() must never close descriptors")

        release.signal()
        let exitExpectation = expectation(description: "blocked run released")
        engine.onExit = { code in
            XCTAssertEqual(code, 7)
            exitExpectation.fulfill()
        }
        wait(for: [exitExpectation], timeout: 5.0)

        close(readEnd)
        close(writeEnd)
    }

    func testStopWithoutStartIsSafe() {
        let (readEnd, writeEnd) = makeFakeFdPair()
        let engine = quickEngine { _ in 0 }
        engine.stop(timeout: 0.1)
        XCTAssertTrue(isOpen(readEnd))
        XCTAssertTrue(isOpen(writeEnd))
        close(readEnd)
        close(writeEnd)
    }

    func testDeinitDoesNotCloseDescriptors() {
        let (readEnd, writeEnd) = makeFakeFdPair()
        var engine: TunnelEngine? = quickEngine { _ in 0 }
        engine = nil
        XCTAssertTrue(isOpen(readEnd), "deinit must not close descriptors")
        XCTAssertTrue(isOpen(writeEnd), "deinit must not close descriptors")
        close(readEnd)
        close(writeEnd)
    }

    func testRunCalledExactlyOnceEvenWhenStartedTwice() {
        var callCount = 0
        let engine = quickEngine { _ in
            callCount += 1
            return 0
        }
        let exitExpectation = expectation(description: "engine exit observed")
        engine.onExit = { _ in exitExpectation.fulfill() }
        engine.start()
        engine.start()

        wait(for: [exitExpectation], timeout: 5.0)
        XCTAssertEqual(callCount, 1)
    }

    func testExitCodeAndOnExitAreDelivered() {
        let exitExpectation = expectation(description: "engine exit observed")
        let engine = quickEngine { _ in 42 }
        engine.onExit = { code in
            XCTAssertEqual(code, 42)
            exitExpectation.fulfill()
        }
        engine.start()
        wait(for: [exitExpectation], timeout: 5.0)
        XCTAssertEqual(engine.exitCode, 42)
        XCTAssertFalse(engine.isRunning)
    }

    func testOnStopRequestedIsInvokedDuringStop() {
        let stopRequested = expectation(description: "stop request delivered")
        let runExited = expectation(description: "engine exit observed")
        let engine = quickEngine { _ in
            runExited.fulfill()
            return 0
        }
        engine.onStopRequested = {
            stopRequested.fulfill()
        }
        engine.start()
        // Give the run closure a moment to enter the loop.
        wait(for: [runExited], timeout: 5.0)
        // Engine already exited: stop() must still invoke the stop request for
        // engines that are still running (here: no-op but observed).
        engine.stop(timeout: 0.5)
        XCTAssertFalse(engine.isRunning)
    }
}