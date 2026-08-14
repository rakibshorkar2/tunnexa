import Foundation
import Network

// MARK: - Staged health test

public enum HealthTestStage: Int, CaseIterable, Comparable {
    case connect = 0
    case greeting = 1
    case auth = 2
    case connectCommand = 3

    public static func < (lhs: HealthTestStage, rhs: HealthTestStage) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .connect: return "TCP Connect"
        case .greeting: return "Greeting"
        case .auth: return "Authentication"
        case .connectCommand: return "CONNECT"
        }
    }
}

public struct HealthTestResult {
    public let proxyId: UUID
    public let status: ProxyStatus
    public let stageLatencies: [HealthTestStage: TimeInterval]
    public let totalLatencyMs: Int?
    public let failureStage: HealthTestStage?
    public let errorDescription: String?

    public init(proxyId: UUID, status: ProxyStatus, stageLatencies: [HealthTestStage: TimeInterval] = [:],
                totalLatencyMs: Int? = nil, failureStage: HealthTestStage? = nil, errorDescription: String? = nil) {
        self.proxyId = proxyId
        self.status = status
        self.stageLatencies = stageLatencies
        self.totalLatencyMs = totalLatencyMs
        self.failureStage = failureStage
        self.errorDescription = errorDescription
    }
}

/// Guarantees the caller's completion fires exactly once, even when several
/// async paths (timeout, connection failure, protocol stages) race.
public final class HealthTestCompletionGate {
    private let completion: (HealthTestResult) -> Void
    private var didFinish = false
    private let lock = NSLock()
    var timeoutWork: DispatchWorkItem?

    public init(completion: @escaping (HealthTestResult) -> Void) {
        self.completion = completion
    }

    /// Delivers the result at most once; always cancels the pending timeout.
    public func finish(_ result: HealthTestResult) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let timeoutWork = timeoutWork
        lock.unlock()

        timeoutWork?.cancel()
        completion(result)
    }
}

// MARK: - Tester

/// Full RFC 1928 CONNECT health probe against a SOCKS5 server.
///
/// Stages (each timed separately):
///  1. TCP connect
///  2. greeting / method negotiation (NO_AUTH + USERNAME/PASSWORD)
///  3. RFC 1929 authentication (when the server requires it)
///  4. CONNECT to a configurable test destination
///
/// A successful CONNECT proves the proxy can actually relay traffic, not just
/// accept sockets. The completion is invoked exactly once, on the main queue.
public enum ProxyHealthTester {

    /// Destination used for the CONNECT stage.
    public static var testHost = "www.gstatic.com"
    public static var testPort: UInt16 = 443
    public static var testTimeout: TimeInterval = 5.0

    public static func testLatency(proxy: SOCKS5Proxy, password: String? = nil, completion: @escaping (HealthTestResult) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(proxy.port)) else {
            DispatchQueue.main.async {
                completion(HealthTestResult(proxyId: proxy.id, status: .protocolError,
                                            failureStage: .connect, errorDescription: "Invalid port \(proxy.port)."))
            }
            return
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(proxy.host), port: port)
        let connection = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue(label: "com.rakib.tunnexa.healthtest.\(proxy.id.uuidString)")
        let gate = HealthTestCompletionGate { result in
            DispatchQueue.main.async { completion(result) }
        }

        let timeoutWork = DispatchWorkItem {
            connection.cancel()
            gate.finish(HealthTestResult(proxyId: proxy.id, status: .timeout,
                                         failureStage: .connect, errorDescription: "Timed out after \(testTimeout)s."))
        }
        gate.timeoutWork = timeoutWork
        queue.asyncAfter(deadline: .now() + testTimeout, execute: timeoutWork)

        let start = Date()
        var stageLatencies: [HealthTestStage: TimeInterval] = [:]

        func record(_ stage: HealthTestStage) {
            stageLatencies[stage] = Date().timeIntervalSince(start)
        }

        func fail(_ status: ProxyStatus, stage: HealthTestStage, reason: String) {
            connection.cancel()
            gate.finish(HealthTestResult(proxyId: proxy.id, status: status,
                                         stageLatencies: stageLatencies, failureStage: stage,
                                         errorDescription: reason))
        }

        func success() {
            connection.cancel()
            let total = Date().timeIntervalSince(start)
            gate.finish(HealthTestResult(proxyId: proxy.id, status: .online,
                                         stageLatencies: stageLatencies,
                                         totalLatencyMs: max(1, Int(total * 1000))))
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                record(.connect)
                sendGreeting()
            case .failed(let error):
                fail(.connFailed, stage: .connect, reason: error.localizedDescription)
            case .waiting(let error):
                if case .posix(let code) = error, code == .ECONNREFUSED {
                    fail(.connFailed, stage: .connect, reason: "Connection refused.")
                }
            default:
                break
            }
        }

        func sendGreeting() {
            var methods: [UInt8] = [0x00]
            if proxy.username != nil || password != nil {
                methods.append(0x02)
            }
            let greeting = Data([0x05, UInt8(methods.count)] + methods)
            connection.send(content: greeting, completion: .contentProcessed { error in
                guard error == nil else {
                    fail(.connFailed, stage: .greeting, reason: "Greeting send failed: \(error!.localizedDescription)")
                    return
                }
                readMethodSelection()
            })
        }

        func readMethodSelection() {
            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
                guard let data = data, data.count == 2, error == nil else {
                    fail(.connFailed, stage: .greeting, reason: "No method selection received.")
                    return
                }
                guard data[0] == 0x05 else {
                    fail(.protocolError, stage: .greeting, reason: "Unexpected SOCKS version \(data[0]).")
                    return
                }
                record(.greeting)
                switch data[1] {
                case 0x00:
                    sendConnectCommand()
                case 0x02:
                    performAuth()
                case 0xFF:
                    fail(.authFailed, stage: .auth, reason: "Server rejected all offered methods.")
                default:
                    fail(.protocolError, stage: .greeting, reason: "Server selected unsupported method 0x\(String(format: "%02x", data[1])).")
                }
            }
        }

        func performAuth() {
            guard let username = proxy.username else {
                fail(.authFailed, stage: .auth, reason: "Server requires authentication but no username is configured.")
                return
            }
            let userBytes = Array(username.utf8)
            let passBytes = Array((password ?? "").utf8)
            guard userBytes.count <= 255, passBytes.count <= 255 else {
                fail(.protocolError, stage: .auth, reason: "Credentials exceed 255 bytes.")
                return
            }
            var auth = Data([0x01, UInt8(userBytes.count)])
            auth.append(contentsOf: userBytes)
            auth.append(UInt8(passBytes.count))
            auth.append(contentsOf: passBytes)

            connection.send(content: auth, completion: .contentProcessed { error in
                guard error == nil else {
                    fail(.connFailed, stage: .auth, reason: "Auth send failed.")
                    return
                }
                connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
                    guard let data = data, data.count == 2, error == nil, data[0] == 0x01 else {
                        fail(.protocolError, stage: .auth, reason: "Malformed auth response.")
                        return
                    }
                    record(.auth)
                    if data[1] == 0x00 {
                        sendConnectCommand()
                    } else {
                        fail(.authFailed, stage: .auth, reason: "Authentication rejected (status \(data[1])).")
                    }
                }
            })
        }

        func sendConnectCommand() {
            var request = Data([0x05, 0x01, 0x00])
            // Test destination is sent as a domain name; the test host is
            // resolved by the proxy itself.
            let hostBytes = Array(testHost.utf8)
            guard !hostBytes.isEmpty, hostBytes.count <= 255 else {
                fail(.protocolError, stage: .connectCommand, reason: "Invalid test host.")
                return
            }
            request.append(0x03)
            request.append(UInt8(hostBytes.count))
            request.append(contentsOf: hostBytes)
            request.append(UInt8((testPort >> 8) & 0xFF))
            request.append(UInt8(testPort & 0xFF))

            connection.send(content: request, completion: .contentProcessed { error in
                guard error == nil else {
                    fail(.connFailed, stage: .connectCommand, reason: "CONNECT send failed.")
                    return
                }
                connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, error in
                    guard let data = data, data.count == 4, error == nil else {
                        fail(.protocolError, stage: .connectCommand, reason: "No CONNECT reply.")
                        return
                    }
                    guard data[1] == 0x00 else {
                        fail(.connFailed, stage: .connectCommand, reason: "CONNECT rejected (code 0x\(String(format: "%02x", data[1]))).")
                        return
                    }
                    // Consume the remainder of the success reply (BND.ADDR/PORT).
                    let atyp = data[3]
                    switch atyp {
                    case 1: consume(6)
                    case 4: consume(18)
                    case 3:
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { lenData, _, _, error in
                            guard let lenData = lenData, lenData.count == 1, error == nil else {
                                fail(.protocolError, stage: .connectCommand, reason: "Truncated CONNECT reply.")
                                return
                            }
                            consume(Int(lenData[0]) + 2)
                        }
                    default:
                        fail(.protocolError, stage: .connectCommand, reason: "Invalid BND.ATYP.")
                    }
                }
            })
        }

        func consume(_ length: Int) {
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { _, _, _, error in
                guard error == nil else {
                    fail(.protocolError, stage: .connectCommand, reason: "Truncated CONNECT reply.")
                    return
                }
                record(.connectCommand)
                success()
            }
        }

        connection.start(queue: queue)
    }
}