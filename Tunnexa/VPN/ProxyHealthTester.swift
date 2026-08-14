import Foundation
import Network

/// Performs a full RFC 1928 compliant SOCKS5 handshake (with optional Username/Password Auth) to measure proxy latency and health.
public struct ProxyHealthTester {

    /// Tests the latency and reachability of a SOCKS5 proxy.
    /// - Parameters:
    ///   - proxy: The proxy to test.
    ///   - completion: Called on the main queue with `(latencyMs: Int?, statusString: String)`.
    public static func testLatency(proxy: SOCKS5Proxy, completion: @escaping (Int?, String) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(proxy.port)) else {
            DispatchQueue.main.async { completion(nil, "Invalid Port") }
            return
        }
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(proxy.host),
            port: port
        )
        
        let connection = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue(label: "com.rakib.tunnexa.healthtest.\(proxy.id.uuidString)")
        let start = Date()

        // 5-second timeout
        let timeoutWork = DispatchWorkItem {
            connection.cancel()
            DispatchQueue.main.async { completion(nil, "Timeout") }
        }
        queue.asyncAfter(deadline: .now() + 5.0, execute: timeoutWork)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Step 1: Send Client Greeting advertising NO_AUTH (0x00) and USERNAME/PASSWORD (0x02)
                let greeting: Data
                if proxy.username != nil || proxy.password != nil {
                    greeting = Data([0x05, 0x02, 0x00, 0x02]) // VER=5, NMETHODS=2, [NO_AUTH, USER/PASS]
                } else {
                    greeting = Data([0x05, 0x01, 0x00]) // VER=5, NMETHODS=1, [NO_AUTH]
                }
                
                connection.send(content: greeting, completion: .contentProcessed({ sendError in
                    if let _ = sendError {
                        timeoutWork.cancel()
                        connection.cancel()
                        DispatchQueue.main.async { completion(nil, "Connection Failed") }
                        return
                    }
                }))

                // Step 2: Read 2-byte server method selection [VER, METHOD]
                connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
                    guard let data = data, data.count == 2, error == nil else {
                        timeoutWork.cancel()
                        connection.cancel()
                        DispatchQueue.main.async { completion(nil, "Connection Failed") }
                        return
                    }

                    guard data[0] == 0x05 else {
                        timeoutWork.cancel()
                        connection.cancel()
                        DispatchQueue.main.async { completion(nil, "Invalid Protocol") }
                        return
                    }

                    let method = data[1]

                    if method == 0xFF {
                        // Server rejected all authentication methods
                        timeoutWork.cancel()
                        connection.cancel()
                        DispatchQueue.main.async { completion(nil, "Authentication Required / Rejected") }
                        return
                    }

                    if method == 0x00 {
                        // NO_AUTH accepted — proxy is online
                        timeoutWork.cancel()
                        connection.cancel()
                        let elapsed = max(1, Int(Date().timeIntervalSince(start) * 1000))
                        DispatchQueue.main.async { completion(elapsed, "Online") }
                        return
                    }

                    if method == 0x02 {
                        // USERNAME/PASSWORD authentication requested (RFC 1929)
                        let user = proxy.username ?? ""
                        let pwd = proxy.password ?? ""
                        
                        var authPacket = Data()
                        authPacket.append(0x01) // Subnegotiation version 1
                        
                        let userBytes = user.data(using: .utf8) ?? Data()
                        authPacket.append(UInt8(min(userBytes.count, 255)))
                        authPacket.append(userBytes)
                        
                        let pwdBytes = pwd.data(using: .utf8) ?? Data()
                        authPacket.append(UInt8(min(pwdBytes.count, 255)))
                        authPacket.append(pwdBytes)

                        connection.send(content: authPacket, completion: .contentProcessed({ sendError in
                            if let _ = sendError {
                                timeoutWork.cancel()
                                connection.cancel()
                                DispatchQueue.main.async { completion(nil, "Auth Send Error") }
                                return
                            }
                        }))

                        // Read 2-byte auth response [VER, STATUS]
                        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { authData, _, _, authError in
                            timeoutWork.cancel()
                            connection.cancel()

                            guard let authData = authData, authData.count == 2, authError == nil else {
                                DispatchQueue.main.async { completion(nil, "Auth Response Error") }
                                return
                            }

                            let status = authData[1]
                            let elapsed = max(1, Int(Date().timeIntervalSince(start) * 1000))

                            if status == 0x00 {
                                // Authentication successful
                                DispatchQueue.main.async { completion(elapsed, "Online") }
                            } else {
                                // Authentication failed (status != 0)
                                DispatchQueue.main.async { completion(nil, "Authentication Failed") }
                            }
                        }
                        return
                    }

                    // Unknown method
                    timeoutWork.cancel()
                    connection.cancel()
                    DispatchQueue.main.async { completion(nil, "Unsupported Method (\(method))") }
                }

            case .failed(let error):
                timeoutWork.cancel()
                connection.cancel()
                DispatchQueue.main.async { completion(nil, "Connection Failed (\(error.localizedDescription))") }

            case .waiting(let error):
                if case .posix(let code) = error, code == .ECONNREFUSED {
                    timeoutWork.cancel()
                    connection.cancel()
                    DispatchQueue.main.async { completion(nil, "Connection Refused") }
                }

            default:
                break
            }
        }

        connection.start(queue: queue)
    }
}
