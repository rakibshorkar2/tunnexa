import XCTest
import Darwin
@testable import Tunnexa

/// Hermetic tests for the TUN descriptor ownership contract and the engine
/// lifecycle. No Tun2SocksKit is required: the engine loop is injected, and
/// ownership is asserted on real descriptors via `fcntl(F_GETFD)`.
final class TunnelEngineTests: XCTestCase {

    /// Creates a pipe and returns (readEnd, writeEnd). The write end stands in
    /// for a TUN descriptor; the read end is returned so the test can close it
    /// and assert EBADF semantics against the write end.
    private func makeFakeFdPair() -> (readEnd: Int32, writeEnd: Int32) {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        return (fds[0], fds[1])
    }

    private func isOpen(_ fd: Int32) -> Bool {
        return fcntl(fd, F_GETFD) != -1
    }

    private func quickEngine(tunFd: Int32, run: @escaping (String) -> Int32) -> TunnelEngine {
        return TunnelEngine(configYAML: "irrelevant", tunFd: tunFd, run: run)
    }

    func testEngineClosesOwnedFdAfterRunExits() {
        let (readEnd, writeEnd) = makeFakeFdPair()
        close(readEnd)
        XCTAssertTrue(isOpen(writeEnd))

        let exitExpectation = expectation(description: "engine exit observed")
        let engine = quickEngine(tunFd: writeEnd) { _ in 0 }
        engine.onExit = { code in
            XCTAssertEqual(code, 0)
            exitExpectation.fulfill()
        }
        engine.start()
        wait(for: [exitExpectation], timeout: 5.0)

        XCTAssertFalse(isOpen(writeEnd), "engine must close the TUN descriptor after the run loop exits")
    }

    func testStopClosesOwnedFdWhenRunDoesNotExit() {
        let (readEnd, writeEnd) = makeFakeFdPair()
        close(readEnd)
        XCTAssertTrue(isOpen(writeEnd))

        let release = DispatchSemaphore(value: 0)
        let engine = quickEngine(tunFd: writeEnd) { _ in
            _ = release.wait(timeout: .now() + 5.0)
            return 7
        }
        engine.start()
        XCTAssertTrue(engine.isRunning)
        XCTAssertNil(engine.exitCode)

        engine.stop(timeout: 0.5)
        XCTAssertFalse(isOpen(writeEnd), "stop() must close the descriptor when the run loop does not exit in time")

        release.signal()
        let exitExpectation = expectation(description: "blocked run released")
        engine.onExit = { code in
            XCTAssertEqual(code, 7)
            exitExpectation.fulfill()
        }
        wait(for: [exitExpectation], timeout: 5.0)
    }

    func testStopWithoutStartClosesFd() {
        let (readEnd, writeEnd) = makeFakeFdPair()
        close(readEnd)
        let engine = quickEngine(tunFd: writeEnd) { _ in 0 }
        engine.stop(timeout: 0.1)
        XCTAssertFalse(isOpen(writeEnd), "stop() must close the descriptor even when the engine never started")
    }

    func testDeinitClosesFd() {
        let (readEnd, writeEnd) = makeFakeFdPair()
        close(readEnd)
        var engine: TunnelEngine? = quickEngine(tunFd: writeEnd) { _ in 0 }
        XCTAssertTrue(isOpen(writeEnd))
        engine = nil
        XCTAssertFalse(isOpen(writeEnd), "deinit must close the descriptor (safety net)")
    }

    func testRunCalledExactlyOnceEvenWhenStartedTwice() {
        let (readEnd, writeEnd) = makeFakeFdPair()
        close(readEnd)
        var callCount = 0
        let engine = quickEngine(tunFd: writeEnd) { _ in
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
        let (readEnd, writeEnd) = makeFakeFdPair()
        close(readEnd)
        let exitExpectation = expectation(description: "engine exit observed")
        let engine = quickEngine(tunFd: writeEnd) { _ in 42 }
        engine.onExit = { code in
            XCTAssertEqual(code, 42)
            exitExpectation.fulfill()
        }
        engine.start()
        wait(for: [exitExpectation], timeout: 5.0)
        XCTAssertEqual(engine.exitCode, 42)
        XCTAssertFalse(engine.isRunning)
    }
}
