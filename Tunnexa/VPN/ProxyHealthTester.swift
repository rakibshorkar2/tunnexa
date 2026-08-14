import Foundation
import Network

/// Performs a real SOCKS5 TCP CONNECT handshake to measure proxy latency and health.
public struct ProxyHealthTester {

    /// Tests the latency and reachability of a SOCKS5 proxy.
    /// - Parameters:
    ///   - proxy: The proxy to test.
    ///   - completion: Called on the main queue with `(latencyMs: Int?, statusString: String)`.
    public static func testLatency(proxy: SOCKS5Proxy, completion: @escaping (Int?, String) -> Void) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(proxy.host),
            port: NWEndpoint.Port(rawValue: UInt16(proxy.port)) ?? 1080
        )
        let connection = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue(label: "com.rakib.tunnexa.healthtest.\(proxy.id.uuidString)")
        let start = Date()

        // Timeout: kill the connection and report timeout after 5 seconds
        let timeoutWork = DispatchWorkItem {
            connection.cancel()
            DispatchQueue.main.async { completion(nil, "Timeout") }
        }
        queue.asyncAfter(deadline: .now() + 5.0, execute: timeoutWork)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Connection established — perform a minimal SOCKS5 greeting
                let greeting = Data([5, 1, 0]) // VER=5, NMETHODS=1, NO_AUTH
                connection.send(content: greeting, completion: .contentProcessed({ _ in }))

                // Read the 2-byte server choice
                connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
                    timeoutWork.cancel()
                    connection.cancel()

                    guard let data = data, data.count == 2, error == nil else {
                        DispatchQueue.main.async { completion(nil, "Connection Failed") }
                        return
                    }

                    // SOCKS5 server must reply with [0x05, method]
                    guard data[0] == 5 else {
                        DispatchQueue.main.async { completion(nil, "Connection Failed") }
                        return
                    }

                    let method = data[1]
                    let elapsed = Int(Date().timeIntervalSince(start) * 1000)

                    if method == 0xFF {
                        // Server rejected all methods
                        DispatchQueue.main.async { completion(nil, "Authentication Failed") }
                    } else if method == 0 || method == 2 {
                        // No auth or username/password auth accepted — proxy is online
                        DispatchQueue.main.async { completion(elapsed, "Online") }
                    } else {
                        DispatchQueue.main.async { completion(nil, "Connection Failed") }
                    }
                }

            case .failed:
                timeoutWork.cancel()
                connection.cancel()
                DispatchQueue.main.async { completion(nil, "Connection Failed") }

            case .waiting(let error):
                if case .posix(let code) = error, code == .ECONNREFUSED {
                    timeoutWork.cancel()
                    connection.cancel()
                    DispatchQueue.main.async { completion(nil, "Connection Failed") }
                }

            default:
                break
            }
        }

        connection.start(queue: queue)
    }
}
