import Foundation
import Darwin

/// Resolves domain names to IP addresses inside the tunnel process.
///
/// The hev-socks5-tunnel engine resolves destinations itself before relaying,
/// but rule evaluation in the dispatcher is synchronous: DOMAIN rules match the
/// domain string, while NETWORK/IP/CIDR rules need IP literals. For domains,
/// the provider optionally feeds resolved addresses into the dispatcher via
/// this service so that IP-scoped rules apply to domain destinations too.
///
/// Results are cached briefly (60 s TTL) so per-connection lookups are cheap.
public final class ProxyEndpointResolver {

    public static let shared = ProxyEndpointResolver()

    private struct CacheEntry {
        let addresses: [String]
        let resolvedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let lock = NSLock()
    private let cacheTTL: TimeInterval = 60.0
    private let workQueue = DispatchQueue(label: "com.rakib.tunnexa.dnsresolver", qos: .utility)

    private init() {}

    /// True when `host` is already an IP literal (IPv4 or IPv6).
    public func isIPAddress(_ host: String) -> Bool {
        return NetworkAddressMatcher.isIPAddress(host)
    }

    /// Synchronous lookup for a hostname using cached results or a fresh
    /// `getaddrinfo` on a background queue.
    public func resolve(host: String, timeout: TimeInterval = 3.0) -> [String] {
        let normalized = host.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return [] }
        if NetworkAddressMatcher.isIPAddress(normalized) {
            return [normalized]
        }

        if let cached = cached(normalized) {
            return cached
        }

        var result: [String] = []
        let semaphore = DispatchSemaphore(value: 0)
        workQueue.async { [weak self] in
            result = self?.lookupAddresses(normalized) ?? []
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)

        if !result.isEmpty {
            lock.lock()
            cache[normalized] = CacheEntry(addresses: result, resolvedAt: Date())
            lock.unlock()
        }
        return result
    }

    /// Asynchronous lookup with cache, matching the dispatcher's resolver
    /// signature (`(host, completion) -> Void`).
    public func resolve(host: String, completion: @escaping ([String]) -> Void) {
        workQueue.async { [weak self] in
            let addresses = self?.resolve(host: host) ?? []
            completion(addresses)
        }
    }

    public func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    private func cached(_ host: String) -> [String]? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache[host] else { return nil }
        guard Date().timeIntervalSince(entry.resolvedAt) < cacheTTL else {
            cache.removeValue(forKey: host)
            return nil
        }
        return entry.addresses
    }

    private func lookupAddresses(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_ADDRCONFIG

        var rawResult: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &rawResult)
        guard status == 0, let head = rawResult else { return [] }
        defer { freeaddrinfo(head) }

        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = head
        while let node = cursor {
            if node.pointee.ai_family == AF_INET {
                var addr = node.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(buffer.count))
                addresses.append(String(cString: buffer))
            } else if node.pointee.ai_family == AF_INET6 {
                var addr = node.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                inet_ntop(AF_INET6, &addr.sin6_addr, &buffer, socklen_t(buffer.count))
                addresses.append(String(cString: buffer))
            }
            cursor = node.pointee.ai_next
        }
        return addresses
    }
}