import Foundation

/// Thread-safe, bounded, rotation-aware logging shared by the app and the
/// Packet Tunnel extension.
///
/// Security contract (enforced centrally):
///  - every message passes through `redactCredentials` before being written;
///  - passwords, usernames and credential-bearing URLs never reach the log file.
public struct SharedLogging {

    public enum Level: Int, Comparable, Codable {
        case debug = 0
        case info = 1
        case notice = 2
        case warning = 3
        case error = 4
        case critical = 5

        public static func < (lhs: Level, rhs: Level) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        public var label: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .notice: return "NOTICE"
            case .warning: return "WARNING"
            case .error: return "ERROR"
            case .critical: return "CRITICAL"
            }
        }
    }

    public enum Category: String {
        case vpn = "VPN"
        case tunnel = "TUNNEL"
        case proxy = "PROXY"
        case yaml = "YAML"
        case dns = "DNS"
        case routing = "ROUTING"
        case network = "NETWORK"
        case security = "SECURITY"
        case diagnostics = "DIAGNOSTICS"
    }

    public struct LogEntry: Identifiable, Equatable {
        public let id: Int
        public let timestamp: Date
        public let level: Level
        public let category: Category
        public let message: String
    }

    // MARK: - Configuration

    public static var minimumLevel: Level = .debug
    public static var maximumLogFileBytes = 512 * 1024

    private static let writeQueue = DispatchQueue(label: "com.rakib.tunnexa.logging")
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static var entryCounter = 0

    // MARK: - File location

    private static func logFileURLs() -> (current: URL?, backup: URL?) {
        let base: URL
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.rakib.tunnexa") {
            base = containerURL
        } else if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            base = caches
        } else {
            return (nil, nil)
        }
        return (base.appendingPathComponent("tunnexa_diagnostics.log"),
                base.appendingPathComponent("tunnexa_diagnostics.log.bak"))
    }

    // MARK: - Logging

    public static func log(_ message: String, category: Category = .network, level: Level = .info) {
        let redacted = redactCredentials(message)
        let timestamp = dateFormatter.string(from: Date())
        let entry = "[\(timestamp)] [\(level.label)] [\(category.rawValue)] \(redacted)"

        // Unified logging (visible in Console.app / device logs)
        NSLog("%@", entry)

        writeQueue.async {
            appendToFile(entry)
        }
    }

    public static func debug(_ message: String, category: Category = .network) {
        log(message, category: category, level: .debug)
    }

    public static func info(_ message: String, category: Category = .network) {
        log(message, category: category, level: .info)
    }

    public static func warning(_ message: String, category: Category = .network) {
        log(message, category: category, level: .warning)
    }

    public static func error(_ message: String, category: Category = .network) {
        log(message, category: category, level: .error)
    }

    public static func critical(_ message: String, category: Category = .network) {
        log(message, category: category, level: .critical)
    }

    // MARK: - File management

    private static func appendToFile(_ entry: String) {
        guard let urls = logFileURLs() as? (current: URL?, backup: URL?), let url = urls.current else { return }
        let line = entry + "\n"

        rotateIfNeeded(current: url, backup: urls.backup)

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func rotateIfNeeded(current: URL, backup: URL?) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: current.path),
              let size = attributes[.size] as? Int, size > maximumLogFileBytes else {
            return
        }
        // Rotate: current -> .bak (dropping any previous backup), fresh file.
        if let backup = backup {
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: current, to: backup)
        } else {
            try? FileManager.default.removeItem(at: current)
        }
    }

    public static func clearLogs() {
        writeQueue.sync {
            guard let urls = logFileURLs() as? (current: URL?, backup: URL?) else { return }
            try? "".write(to: urls.current!, atomically: true, encoding: .utf8)
            if let backup = urls.backup {
                try? FileManager.default.removeItem(at: backup)
            }
        }
    }

    public static func readLogs() -> String {
        var result = ""
        writeQueue.sync {
            guard let urls = logFileURLs() as? (current: URL?, backup: URL?) else { return }
            if let backup = urls.backup, let content = try? String(contentsOf: backup, encoding: .utf8) {
                result += content
            }
            if let current = urls.current, let content = try? String(contentsOf: current, encoding: .utf8) {
                result += content
            }
        }
        if result.isEmpty { return "No logs available." }
        return result
    }

    /// Parsed log entries (used by the Diagnostics UI for filtering).
    public static func readEntries() -> [LogEntry] {
        let raw = readLogs()
        var entries: [LogEntry] = []
        let pattern = "^\\[([0-9\\- :.]+)\\] \\[([A-Z]+)\\] \\[([A-Z]+)\\] (.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            guard !line.isEmpty,
                  let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) else { continue }
            let ts = String(line[Range(match.range(at: 1), in: line)!])
            let levelRaw = String(line[Range(match.range(at: 2), in: line)!])
            let categoryRaw = String(line[Range(match.range(at: 3), in: line)!])
            let message = String(line[Range(match.range(at: 4), in: line)!])
            let level = Level.allLevels.first(where: { $0.label == levelRaw }) ?? .info
            let category = Category(rawValue: categoryRaw) ?? .network
            entryCounter += 1
            entries.append(LogEntry(id: entryCounter, timestamp: Date(), level: level, category: category, message: message))
        }
        return entries
    }

    // MARK: - Credential Redaction

    /// Redacts credentials from arbitrary log text.
    /// Handles, among others:
    ///  - `password=value`, `password: value`, `"password":"value"`, `'password': 'value'`
    ///  - `username=value`, `"username": "value"`
    ///  - `proxy://user:password@host`, `socks5://user:password@host:1080`
    ///  - raw quoted secrets next to known key names
    public static func redactCredentials(_ input: String) -> String {
        var output = input
        let rawPatterns: [(String, String)] = [
            // URL userinfo: scheme://user:pass@host -> scheme://[REDACTED]@host
            ("([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@\\s]+@", "$1[REDACTED]@"),
            // JSON style: "password":"value" / "password" : "value"
            ("(?i)(\"(?:password|passwd|pwd|username|auth_token)\"\\s*:\\s*)\"[^\"]*\"", "$1\"[REDACTED]\""),
            // Single quoted: 'password': 'value'
            ("(?i)('(?:password|passwd|pwd|username|auth_token)'\\s*:\\s*)'[^']*'", "$1'[REDACTED]'"),
            // Key = "value" or Key = value (normalized to "Key: [REDACTED]")
            ("(?i)\\b(password|passwd|pwd|username|auth_token|client_secret)\\s*=\\s*[\"']?[^\"',\\n\\r\\s}]+", "$1: [REDACTED]"),
            // Key: 'value' or Key: "value"
            ("(?i)\\b(password|passwd|pwd|username|auth_token|client_secret)\\s*:\\s*[\"'][^\"']*[\"']", "$1: [REDACTED]"),
            // Key: value
            ("(?i)\\b(password|passwd|pwd|username|auth_token|client_secret)\\s*:\\s*[^\"'\\s,}\\[\\]{}]+", "$1: [REDACTED]"),
        ]

        for (pattern, template) in rawPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: template)
        }
        return output
    }
}

extension SharedLogging.Level {
    static let allLevels: [SharedLogging.Level] = [.debug, .info, .notice, .warning, .error, .critical]
}