import Foundation

public struct SharedLogging {
    public enum Category: String {
        case vpn = "VPN"
        case tunnel = "TUNNEL"
        case proxy = "PROXY"
        case yaml = "YAML"
        case dns = "DNS"
        case routing = "ROUTING"
        case network = "NETWORK"
    }
    
    private static var logFileURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.rakib.tunnexa") else {
            return nil
        }
        return containerURL.appendingPathComponent("tunnexa_diagnostics.log")
    }
    
    public static func log(_ message: String, category: Category = .network) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let redacted = redactCredentials(message)
        let logLine = "[\(timestamp)] [\(category.rawValue)] \(redacted)\n"
        
        // Output to Apple System Log
        NSLog("%@", logLine)
        
        // Append to shared log file
        guard let url = logFileURL else { return }
        
        if let fileHandle = try? FileHandle(forWritingTo: url) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            if let data = logLine.data(using: .utf8) {
                fileHandle.write(data)
            }
        } else {
            try? logLine.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    public static func clearLogs() {
        guard let url = logFileURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }
    
    public static func readLogs() -> String {
        guard let url = logFileURL, let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "No logs available."
        }
        return content
    }
    
    public static func redactCredentials(_ input: String) -> String {
        var output = input
        
        // Redact "password: xyz" or "password=xyz" or "password":"xyz"
        let patterns = [
            ("password\\s*[:=]\\s*\"?[^\",\\n\\r\"]+\"?", "password: [REDACTED]"),
            ("username\\s*[:=]\\s*\"?[^\",\\n\\r\"]+\"?", "username: [REDACTED]")
        ]
        
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(output.startIndex..., in: output)
                output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: replacement)
            }
        }
        
        return output
    }
}
