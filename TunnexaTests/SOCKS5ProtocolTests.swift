import XCTest
import Network
@testable import Tunnexa

// MARK: - Hermetic In-Process Test Infrastructure
//
// These tests exercise the real `LocalProxyServer` over loopback sockets.
// No external network is required: every "remote" end is an NWListener in
// this test process.

/// Starts an NWListener and waits until it is ready (or failed).
///
/// `NWListener.port` reports raw value 0 until the listener transitions to
/// `.ready`, so the assigned port must never be captured before readiness —
/// otherwise clients connect to 127.0.0.1:0 and fail with EADDRNOTAVAIL.
///
/// Transient `.failed(posix 22)` states are observed on the iOS simulator
/// when a loopback listener races the necp socket setup; retry a few times
/// before giving up.
func startListenerAndWaitReady(_ listener: NWListener, queue: DispatchQueue) throws -> UInt16 {
    var lastFailure: Error?
    for attempt in 0..<3 {
        let ready = DispatchSemaphore(value: 0)
        var failure: NWError?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed(let error):
                failure = error
                ready.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)
        ready.wait()
        if let failure = failure {
            lastFailure = failure
            if attempt < 2 {
                listener.cancel()
                Thread.sleep(forTimeInterval: 0.15)
                continue
            }
            throw failure
        }
        return listener.port!.rawValue
    }
    throw lastFailure ?? POSIXError(.EINVAL)
}

/// Picks a free loopback TCP port by binding and releasing a temporary listener.
/// Never crashes: returns 0 on persistent failure (tests then fail with
/// assertion errors instead of killing the test process).
func allocateLoopbackPort() -> UInt16 {
    for _ in 0..<5 {
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            let queue = DispatchQueue(label: "com.rakib.tunnexa.tests.portalloc")
            let port = try startListenerAndWaitReady(listener, queue: queue)
            listener.cancel()
            return port
        } catch {
            Thread.sleep(forTimeInterval: 0.15)
        }
    }
    return 0
}

/// Minimal echo server on loopback. Returns its port.
final class LoopbackEchoServer {
    let port: UInt16
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.rakib.tunnexa.tests.echo")

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: .any)
        port = try startListenerAndWaitReady(listener, queue: queue)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.echo(connection)
        }
    }

    private func echo(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                connection.send(content: data, completion: .contentProcessed { _ in
                    self?.echo(connection)
                })
            } else if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    func stop() {
        listener.cancel()
        connections.forEach { $0.cancel() }
    }
}

/// Raw loopback SOCKS5 test client (speaks the wire protocol by hand).
final class Socks5TestClient {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.rakib.tunnexa.tests.client")
    private var pendingReceive: ((Data?, NWError?) -> Void)?

    init(port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!
        )
        connection = NWConnection(to: endpoint, using: .tcp)
    }

    func start() {
        connection.start(queue: queue)
    }

    func send(_ data: Data, completion: @escaping (NWError?) -> Void = { _ in }) {
        connection.send(content: data, completion: .contentProcessed(completion))
    }

    func receive(minimum: Int, maximum: Int, completion: @escaping (Data?, NWError?) -> Void) {
        pendingReceive = completion
        connection.receive(minimumIncompleteLength: minimum, maximumLength: maximum) { [weak self] data, _, _, error in
            let handler = self?.pendingReceive
            self?.pendingReceive = nil
            handler?(data, error)
        }
    }

    func cancel() {
        connection.cancel()
    }
}

final class SOCKS5ProtocolTests: XCTestCase {

    var dispatcher: LocalProxyServer!
    var dispatcherPort: UInt16!
    var settings: SharedSettings!
    var suiteName: String!
    var echoServer: LoopbackEchoServer!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.rakib.tunnexa_test_\(UUID().uuidString)"
        settings = SharedSettings(suiteName: suiteName)
        dispatcherPort = allocateLoopbackPort()
        dispatcher = LocalProxyServer(port: dispatcherPort, settings: settings)
        do {
            try dispatcher.start()
        } catch {
            XCTFail("Dispatcher failed to start: \(error)")
        }
        do {
            echoServer = try LoopbackEchoServer()
        } catch {
            XCTFail("Echo server failed to start: \(error)")
        }
    }

    override func tearDown() {
        echoServer.stop()
        dispatcher.stop()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// config with rules: MATCH -> DIRECT. No selection needed.
    private func installDirectConfig() {
        let config = ProxyConfiguration(
            proxies: [],
            groups: [],
            rules: [Rule(type: .match, payload: nil, target: RouteDirect)]
        )
        settings.saveConfiguration(config)
        settings.selectedProxyName = ""
        settings.selectedGroupName = ""
        dispatcher.loadConfig()
    }

    // MARK: - Full CONNECT round trip (DIRECT)

    func testDirectConnectRelaysBidirectionalData() {
        installDirectConfig()

        let expectation = XCTestExpectation(description: "full CONNECT + echo round trip")

        let client = Socks5TestClient(port: dispatcherPort)
        client.start()

        // 1) Greeting: offer NO_AUTH only.
        client.send(Data([0x05, 0x01, 0x00]))
        client.receive(minimum: 2, maximum: 2) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, Data([0x05, 0x00]), "Server must accept NO_AUTH")

            // 2) CONNECT to the loopback echo server (IPv4 ATYP).
            var request = Data([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1])
            request.append(UInt8((self.echoServer.port >> 8) & 0xFF))
            request.append(UInt8(self.echoServer.port & 0xFF))
            client.send(request)

            // 3) Reply must be success (0x00) + IPv4 BND.
            client.receive(minimum: 10, maximum: 10) { data, error in
                XCTAssertNil(error)
                XCTAssertEqual(data?.first, 0x05)
                XCTAssertEqual(data?[1], 0x00, "CONNECT must succeed")

                // 4) Send payload, expect the echo back.
                client.send(Data("ping-through-vpn".utf8))
                client.receive(minimum: 14, maximum: 14) { echoData, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(String(data: echoData ?? Data(), encoding: .utf8), "ping-through-vpn")
                    expectation.fulfill()
                }
            }
        }

        wait(for: [expectation], timeout: 10)
        client.cancel()
    }

    // MARK: - BLOCK route

    func testBlockedRouteReturnsNotAllowedAndCloses() {
        let config = ProxyConfiguration(
            proxies: [],
            groups: [],
            rules: [Rule(type: .match, payload: nil, target: RouteBlocked)]
        )
        settings.saveConfiguration(config)
        settings.selectedProxyName = ""
        settings.selectedGroupName = ""
        dispatcher.loadConfig()

        let expectation = XCTestExpectation(description: "BLOCK reply")
        let client = Socks5TestClient(port: dispatcherPort)
        client.start()

        client.send(Data([0x05, 0x01, 0x00]))
        client.receive(minimum: 2, maximum: 2) { _, _ in
            var request = Data([0x05, 0x01, 0x00, 0x01, 93, 184, 216, 34])
            request.append(UInt8((443 >> 8) & 0xFF))
            request.append(UInt8(443 & 0xFF))
            client.send(request)
            client.receive(minimum: 10, maximum: 10) { data, error in
                XCTAssertNil(error)
                XCTAssertEqual(data?[1], 0x02, "BLOCK must answer REP 0x02 (not allowed)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10)
        client.cancel()
    }

    // MARK: - No selection, no rules -> fail closed

    func testNoSelectionWithoutRulesRejectsConnection() {
        // Empty config, no rules, no selection.
        settings.saveConfiguration(ProxyConfiguration(proxies: [], groups: [], rules: []))
        settings.selectedProxyName = ""
        settings.selectedGroupName = ""
        dispatcher.loadConfig()

        let expectation = XCTestExpectation(description: "no selection reply")
        let client = Socks5TestClient(port: dispatcherPort)
        client.start()

        client.send(Data([0x05, 0x01, 0x00]))
        client.receive(minimum: 2, maximum: 2) { _, _ in
            var request = Data([0x05, 0x01, 0x00, 0x01, 8, 8, 8, 8])
            request.append(UInt8((53 >> 8) & 0xFF))
            request.append(UInt8(53 & 0xFF))
            client.send(request)
            client.receive(minimum: 10, maximum: 10) { data, _ in
                XCTAssertEqual(data?[1], 0x02, "Without rules or selection the dispatcher must fail closed (0x02)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10)
        client.cancel()
    }

    // MARK: - Unsupported command

    func testUnsupportedCommandReturnsCommandNotSupported() {
        installDirectConfig()
        let expectation = XCTestExpectation(description: "unsupported command reply")
        let client = Socks5TestClient(port: dispatcherPort)
        client.start()

        client.send(Data([0x05, 0x01, 0x00]))
        client.receive(minimum: 2, maximum: 2) { _, _ in
            // BIND (0x02) is not supported.
            var request = Data([0x05, 0x02, 0x00, 0x01, 127, 0, 0, 1])
            request.append(UInt8((80 >> 8) & 0xFF))
            request.append(UInt8(80 & 0xFF))
            client.send(request)
            client.receive(minimum: 10, maximum: 10) { data, _ in
                XCTAssertEqual(data?[1], 0x07, "BIND must be answered with REP 0x07")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10)
        client.cancel()
    }

    // MARK: - Local auth (RFC 1929)

    func testLocalAuthRequiredAndRejected() {
        settings.set(true, forKey: SettingsKey.localAuthEnabled)
        settings.set("tunuser", forKey: SettingsKey.localAuthUsername)
        settings.set("tunpass", forKey: SettingsKey.localAuthPassword)
        installDirectConfig()

        let wrongExpectation = XCTestExpectation(description: "wrong credentials rejected")
        let wrongClient = Socks5TestClient(port: dispatcherPort)
        wrongClient.start()

        // Offer NO_AUTH + USERNAME/PASSWORD.
        wrongClient.send(Data([0x05, 0x02, 0x00, 0x02]))
        wrongClient.receive(minimum: 2, maximum: 2) { data, _ in
            XCTAssertEqual(data, Data([0x05, 0x02]), "Server must require RFC 1929 auth")

            // Send wrong credentials.
            var auth = Data([0x01, 0x07])
            auth.append(contentsOf: Array("tunuser".utf8))
            auth.append(UInt8("wrongpass".utf8.count))
            auth.append(contentsOf: Array("wrongpass".utf8))
            wrongClient.send(auth)

            wrongClient.receive(minimum: 2, maximum: 2) { authReply, _ in
                XCTAssertEqual(authReply, Data([0x01, 0x01]), "Wrong credentials must be rejected")
                wrongExpectation.fulfill()
            }
        }
        wait(for: [wrongExpectation], timeout: 10)
        wrongClient.cancel()

        let correctExpectation = XCTestExpectation(description: "correct credentials accepted")
        let client = Socks5TestClient(port: dispatcherPort)
        client.start()

        client.send(Data([0x05, 0x02, 0x00, 0x02]))
        client.receive(minimum: 2, maximum: 2) { _, _ in
            var auth = Data([0x01, 0x07])
            auth.append(contentsOf: Array("tunuser".utf8))
            auth.append(UInt8("tunpass".utf8.count))
            auth.append(contentsOf: Array("tunpass".utf8))
            client.send(auth)

            client.receive(minimum: 2, maximum: 2) { authReply, _ in
                XCTAssertEqual(authReply, Data([0x01, 0x00]), "Correct credentials must be accepted")

                var request = Data([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1])
                request.append(UInt8((self.echoServer.port >> 8) & 0xFF))
                request.append(UInt8(self.echoServer.port & 0xFF))
                client.send(request)
                client.receive(minimum: 10, maximum: 10) { reply, _ in
                    XCTAssertEqual(reply?[1], 0x00, "CONNECT must succeed after successful auth")
                    correctExpectation.fulfill()
                }
            }
        }

        wait(for: [correctExpectation], timeout: 10)
        client.cancel()
    }

    // MARK: - Upstream proxy round trip (credential handoff through the store)

    func testConnectViaUpstreamProxyUsesCredentialStore() {
        // Mock upstream SOCKS5 proxy that requires auth and echoes data.
        let upstream = MockSocksServer(behavior: .authRequired)
        try! upstream.start()

        let config = ProxyConfiguration(
            proxies: [SOCKS5Proxy(name: "Upstream", host: "127.0.0.1", port: Int(upstream.port), username: "proxyuser")],
            groups: [],
            rules: [Rule(type: .match, payload: nil, target: "Upstream")]
        )
        settings.saveConfiguration(config)
        settings.selectedProxyName = ""
        settings.selectedGroupName = ""

        // Password lives ONLY in the credential store (never in the config).
        let credentialStore = InMemoryCredentialStore()
        credentialStore.savePassword("proxypass", forProxyId: config.proxies[0].id.uuidString)
        dispatcher = LocalProxyServer(port: dispatcherPort, settings: settings, credentialStore: credentialStore)
        try! dispatcher.start()
        dispatcher.loadConfig()

        let expectation = XCTestExpectation(description: "via upstream proxy")
        let client = Socks5TestClient(port: dispatcherPort)
        client.start()

        client.send(Data([0x05, 0x01, 0x00]))
        client.receive(minimum: 2, maximum: 2) { _, _ in
            var request = Data([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1])
            request.append(UInt8((self.echoServer.port >> 8) & 0xFF))
            request.append(UInt8(self.echoServer.port & 0xFF))
            client.send(request)

            client.receive(minimum: 10, maximum: 10) { reply, _ in
                XCTAssertEqual(reply?[1], 0x00, "Dispatched CONNECT must succeed via the upstream proxy")

                client.send(Data("creds-from-store".utf8))
                client.receive(minimum: 15, maximum: 15) { echo, _ in
                    XCTAssertEqual(String(data: echo ?? Data(), encoding: .utf8), "creds-from-store")
                    XCTAssertEqual(upstream.lastAuthUsername, "proxyuser")
                    XCTAssertEqual(upstream.lastAuthPassword, "proxypass")
                    expectation.fulfill()
                }
            }
        }

        wait(for: [expectation], timeout: 10)
        client.cancel()
        upstream.stop()
    }
}

// MARK: - Mock SOCKS5 upstream server

final class MockSocksServer {
    enum Behavior {
        case online
        case authRequired
        case authRejected
        case connectRejected
        case silent
    }

    let behavior: Behavior
    private(set) var port: UInt16 = 0
    private var listener: NWListener!
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.rakib.tunnexa.tests.mocksocks")
    private let stateLock = NSLock()
    private var capturedUsername: String?
    private var capturedPassword: String?

    var lastAuthUsername: String? {
        stateLock.lock(); defer { stateLock.unlock() }
        return capturedUsername
    }
    var lastAuthPassword: String? {
        stateLock.lock(); defer { stateLock.unlock() }
        return capturedPassword
    }

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    /// Starts the mock; on listener failure records a test failure instead of
    /// crashing the test process (a process crash discards the whole run).
    func startOrFail(_ testCase: XCTestCase) {
        do {
            try start()
        } catch {
            testCase.record(XCTIssue(
                type: .assertionFailure,
                compactDescription: "MockSocksServer failed to start: \(error)"
            ))
        }
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let boundListener = try NWListener(using: parameters, on: .any)
        listener = boundListener
        port = try startListenerAndWaitReady(boundListener, queue: queue)
        boundListener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.handle(connection)
        }
    }

    private func handle(_ connection: NWConnection) {
        guard behavior != .silent else { return } // accept and never respond
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 2, error == nil else {
                connection.cancel()
                return
            }
            switch self.behavior {
            case .authRequired, .authRejected:
                connection.send(content: Data([0x05, 0x02]), completion: .contentProcessed { _ in
                    self.readAuth(connection)
                })
            default:
                connection.send(content: Data([0x05, 0x00]), completion: .contentProcessed { _ in
                    self.readConnect(connection)
                })
            }
        }
    }

    /// RFC 1929 sub-negotiation: [VER(1) ULEN(1) UNAME PLEN(1) PASS].
    private func readAuth(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 2, error == nil else {
                connection.cancel()
                return
            }
            let usernameLength = Int(data[1])
            connection.receive(minimumIncompleteLength: usernameLength, maximumLength: usernameLength) { usernameData, _, _, error in
                guard let usernameData = usernameData, usernameData.count == usernameLength, error == nil else {
                    connection.cancel()
                    return
                }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { passLenData, _, _, error in
                    guard let passLenData = passLenData, passLenData.count == 1, error == nil else {
                        connection.cancel()
                        return
                    }
                    let passwordLength = Int(passLenData[0])
                    connection.receive(minimumIncompleteLength: passwordLength, maximumLength: passwordLength) { passData, _, _, error in
                        guard let passData = passData, passData.count == passwordLength, error == nil else {
                            connection.cancel()
                            return
                        }
                        self.stateLock.lock()
                        self.capturedUsername = String(data: usernameData, encoding: .utf8)
                        self.capturedPassword = String(data: passData, encoding: .utf8)
                        self.stateLock.unlock()

                        if self.behavior == .authRejected {
                            connection.send(content: Data([0x01, 0x01]), completion: .contentProcessed { _ in
                                connection.cancel()
                            })
                        } else {
                            connection.send(content: Data([0x01, 0x00]), completion: .contentProcessed { _ in
                                self.readConnect(connection)
                            })
                        }
                    }
                }
            }
        }
    }

    private func readConnect(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 4, error == nil else {
                connection.cancel()
                return
            }
            let atyp = data[3]
            switch atyp {
            case 1:
                self.consume(connection, length: 6)
            case 4:
                self.consume(connection, length: 18)
            case 3:
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { lenData, _, _, _ in
                    guard let lenData = lenData, lenData.count == 1 else {
                        connection.cancel()
                        return
                    }
                    self.consume(connection, length: Int(lenData[0]) + 2)
                }
            default:
                connection.cancel()
            }
        }
    }

    private func consume(_ connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] _, _, _, error in
            guard error == nil else {
                connection.cancel()
                return
            }
            let code: UInt8 = (self?.behavior == .connectRejected) ? 0x05 : 0x00
            connection.send(content: Data([0x05, code, 0x00, 0x01, 127, 0, 0, 1, 0, 0]), completion: .contentProcessed { _ in
                if let self = self, self.behavior == .online || self.behavior == .authRequired {
                    self.echo(connection)
                }
            })
        }
    }

    private func echo(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                connection.send(content: data, completion: .contentProcessed { _ in
                    self?.echo(connection)
                })
            } else if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
    }
}