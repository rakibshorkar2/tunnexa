import XCTest
@testable import Tunnexa

final class YAMLParserTests: XCTestCase {

    // MARK: - Valid configuration

    func testYAMLParserValidConfig() throws {
        let yamlContent = """
        proxies:
          - name: "Server-1"
            type: socks5
            server: 192.0.2.10
            port: 1080
            username: user1
            password: pass1
          - name: "Server-2"
            type: socks5
            server: 192.0.2.20
            port: 1080

        proxy-groups:
          - name: "BypassEmpire"
            type: select
            proxies:
              - "Server-1"
              - "Server-2"

        rules:
          - DOMAIN-SUFFIX,google.com,BypassEmpire
          - MATCH,BypassEmpire
        """

        let config = try YAMLParser.parse(yamlContent)

        // Assert proxies
        XCTAssertEqual(config.proxies.count, 2)
        XCTAssertEqual(config.proxies[0].name, "Server-1")
        XCTAssertEqual(config.proxies[0].host, "192.0.2.10")
        XCTAssertEqual(config.proxies[0].port, 1080)
        XCTAssertEqual(config.proxies[0].username, "user1")
        XCTAssertEqual(config.proxies[0].password, "pass1")

        XCTAssertNil(config.proxies[1].username)
        XCTAssertNil(config.proxies[1].password)

        // Assert groups (regression: groups used to be flushed with EMPTY proxy lists)
        XCTAssertEqual(config.groups.count, 1)
        XCTAssertEqual(config.groups[0].name, "BypassEmpire")
        XCTAssertEqual(config.groups[0].type, .select)
        XCTAssertEqual(config.groups[0].proxies.count, 2)
        XCTAssertEqual(config.groups[0].proxies[0], "Server-1")
        XCTAssertEqual(config.groups[0].proxies[1], "Server-2")

        // Assert rules
        XCTAssertEqual(config.rules.count, 2)
        XCTAssertEqual(config.rules[0].type, .domainSuffix)
        XCTAssertEqual(config.rules[0].payload, "google.com")
        XCTAssertEqual(config.rules[0].target, "BypassEmpire")

        XCTAssertEqual(config.rules[1].type, .match)
        XCTAssertNil(config.rules[1].payload)
        XCTAssertEqual(config.rules[1].target, "BypassEmpire")
    }

    func testSampleConfigImports() throws {
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("bypassempire (2).yaml")
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            throw XCTSkip("Sample config not available in test sandbox.")
        }
        let config = try YAMLParser.parse(content)
        XCTAssertEqual(config.proxies.count, 17)
        XCTAssertEqual(config.groups.count, 2)
        XCTAssertEqual(config.groups[0].type, .select)
        XCTAssertEqual(config.groups[1].type, .loadBalance)
        XCTAssertEqual(config.rules.count, 5)
        XCTAssertEqual(config.rules.last?.target, "BypassEmpire")
    }

    func testGroupReferencingGroupResolves() throws {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
        proxy-groups:
          - name: "GroupA"
            type: select
            proxies:
              - A
          - name: "GroupB"
            type: load-balance
            proxies:
              - "GroupA"
        rules:
          - MATCH,GroupB
        """
        let config = try YAMLParser.parse(yamlContent)
        XCTAssertEqual(config.groups.count, 2)
        XCTAssertEqual(config.groups[1].proxies, ["GroupA"])
    }

    func testUnresolvedReferenceFailsValidation() {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
        rules:
          - MATCH,DoesNotExist
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.validation(let issues) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.reason.contains("DoesNotExist") })
        }
    }

    func testDuplicateProxyNamesFail() {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
          - name: A
            type: socks5
            server: 192.0.2.2
            port: 1081
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.validation(let issues) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.reason.contains("Duplicate proxy name") })
        }
    }

    func testUnsupportedProxyTypeSkippedWithWarning() throws {
        let yamlContent = """
        proxies:
          - name: VMess
            type: vmess
            server: 192.0.2.1
            port: 8388
          - name: Socks
            type: socks5
            server: 192.0.2.2
            port: 1080
        """
        let summary = try YAMLParser.parseDetailed(yamlContent)
        XCTAssertEqual(summary.configuration.proxies.count, 1)
        XCTAssertEqual(summary.configuration.proxies[0].name, "Socks")
        XCTAssertEqual(summary.skippedProxies, 1)
        XCTAssertEqual(summary.warnings.count, 1)
    }

    func testUnsupportedRuleTypeSkippedWithWarning() throws {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
        rules:
          - GEOIP,CN,DIRECT
          - MATCH,A
        """
        let summary = try YAMLParser.parseDetailed(yamlContent)
        XCTAssertEqual(summary.configuration.rules.count, 1)
        XCTAssertEqual(summary.skippedRules, 1)
    }

    func testEmptyGroupFailsValidation() {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
        proxy-groups:
          - name: "Empty"
            type: select
            proxies:
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.validation(let issues) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.reason.contains("has no members") })
        }
    }

    func testMalformedRuleFailsValidation() {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
        rules:
          - DOMAIN-SUFFIX,google.com
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.validation(let issues) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.reason.contains("must have a payload and a target") })
        }
    }

    func testInvalidNetworkPayloadFailsValidation() {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
        rules:
          - NETWORK,999.1.1.1,DIRECT
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.validation(let issues) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.reason.contains("NETWORK rule payload") })
        }
    }

    func testValidNetworkPayloads() throws {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
        rules:
          - NETWORK,UDP,DIRECT
          - NETWORK,TCP,A
          - NETWORK,192.168.0.0/16,DIRECT
          - NETWORK,10.0.0.1,BLOCK
          - MATCH,A
        """
        let config = try YAMLParser.parse(yamlContent)
        XCTAssertEqual(config.rules.count, 5)
    }

    // MARK: - Parser edge cases

    func testCRLFAndInlineComments() throws {
        let yamlContent = "proxies:\r\n  - name: A # trailing comment\r\n    type: socks5\r\n    server: 192.0.2.1 # inline\r\n    port: 1080 # note\r\nrules:\r\n  - MATCH,A # fallback\r\n"
        let config = try YAMLParser.parse(yamlContent)
        XCTAssertEqual(config.proxies.count, 1)
        XCTAssertEqual(config.proxies[0].name, "A")
        XCTAssertEqual(config.proxies[0].host, "192.0.2.1")
        XCTAssertEqual(config.proxies[0].port, 1080)
        XCTAssertEqual(config.rules.count, 1)
    }

    func testQuotedValuesWithColonsAndHashes() throws {
        let yamlContent = """
        proxies:
          - name: "Proxy: Primary"
            type: socks5
            server: 192.0.2.1
            port: "1080"
            password: "p#ss:word"
        """
        let config = try YAMLParser.parse(yamlContent)
        XCTAssertEqual(config.proxies[0].name, "Proxy: Primary")
        XCTAssertEqual(config.proxies[0].port, 1080)
        XCTAssertEqual(config.proxies[0].password, "p#ss:word")
    }

    func testSingleQuotedValues() throws {
        let yamlContent = """
        proxies:
          - name: 'Server'
            type: 'socks5'
            server: '192.0.2.1'
            port: '1080'
        """
        let config = try YAMLParser.parse(yamlContent)
        XCTAssertEqual(config.proxies[0].name, "Server")
        XCTAssertEqual(config.proxies[0].port, 1080)
    }

    func testTabIndentationRejected() {
        let yamlContent = "proxies:\n\t- name: A\n\t  type: socks5\n\t  server: 192.0.2.1\n\t  port: 1080\n"
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.invalidStructure(let line, let message) = error else {
                return XCTFail("Expected invalidStructure, got \(error)")
            }
            XCTAssertEqual(line, 2)
            XCTAssertTrue(message.contains("Tab"))
        }
    }

    func testInconsistentIndentationRejected() {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
           server: 192.0.2.1
            port: 1080
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.invalidStructure = error else {
                return XCTFail("Expected invalidStructure, got \(error)")
            }
        }
    }

    func testEmptyListItemRejected() {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
          -
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.invalidStructure(let line, _) = error else {
                return XCTFail("Expected invalidStructure, got \(error)")
            }
            XCTAssertEqual(line, 6)
        }
    }

    func testUnknownGroupTypeFailsValidation() {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
        proxy-groups:
          - name: "Fallback"
            type: url-test
            proxies:
              - A
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.validation(let issues) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.reason.contains("unsupported type 'url-test'") })
        }
    }

    // MARK: - Missing / empty sections

    func testYAMLParserMissingProxiesThrows() {
        let yamlContent = """
        rules:
          - MATCH,DIRECT
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            XCTAssertTrue(error is YAMLParsingError)
        }
    }

    func testYAMLParserInvalidPortThrows() {
        let yamlContent = """
        proxies:
          - name: "BadServer"
            type: socks5
            server: 192.0.2.10
            port: 99999
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            XCTAssertTrue(error is YAMLParsingError)
        }
    }

    func testEmptyDocumentThrows() {
        XCTAssertThrowsError(try YAMLParser.parse("")) { error in
            XCTAssertTrue(error is YAMLParsingError)
        }
    }

    // MARK: - Redaction (kept in this file for continuity)

    func testCredentialRedaction() {
        let logLine = "Connecting with username=rakib and password=mysecretpassword"
        let redacted = SharedLogging.redactCredentials(logLine)

        XCTAssertTrue(redacted.contains("password: [REDACTED]"))
        XCTAssertTrue(redacted.contains("username: [REDACTED]"))
        XCTAssertFalse(redacted.contains("mysecretpassword"))
        XCTAssertFalse(redacted.contains("rakib"))
    }

    func testRedactionHandlesURLUserInfo() {
        let logLine = "Proxying via socks5://user:hunter2@example.com:1080"
        let redacted = SharedLogging.redactCredentials(logLine)
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertFalse(redacted.contains("user:hunter2"))
        XCTAssertTrue(redacted.contains("example.com:1080"))
    }

    func testRedactionHandlesJSONStyle() {
        let logLine = #"{"name":"A","password":"hunter2","username":"bob"}"#
        let redacted = SharedLogging.redactCredentials(logLine)
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertFalse(redacted.contains("bob"))
        XCTAssertTrue(redacted.contains("[REDACTED]"))
    }

    func testRedactionDoesNotScrubNormalText() {
        let logLine = "Server is responding, latency 45ms, routing via BypassEmpire"
        let redacted = SharedLogging.redactCredentials(logLine)
        XCTAssertEqual(redacted, logLine)
    }

    // MARK: - Hardening: duplicate keys and resource limits

    func testDuplicateMappingKeyRejected() {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
            port: 1081
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.invalidStructure(let line, let message) = error else {
                return XCTFail("Expected invalidStructure, got \(error)")
            }
            XCTAssertTrue(message.contains("Duplicate key 'port'"), "Unexpected message: \(message)")
            XCTAssertEqual(line, 5)
        }
    }

    func testDuplicateTopLevelKeyRejected() {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
        proxies:
          - name: B
            type: socks5
            server: 192.0.2.2
            port: 1080
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.invalidStructure(_, let message) = error else {
                return XCTFail("Expected invalidStructure, got \(error)")
            }
            XCTAssertTrue(message.contains("Duplicate key 'proxies'"))
        }
    }

    func testDuplicateContinuationKeyRejected() {
        let yamlContent = """
        proxies:
          - name: A
            type: socks5
            server: 192.0.2.1
            port: 1080
            name: B
        """
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.invalidStructure(_, let message) = error else {
                return XCTFail("Expected invalidStructure, got \(error)")
            }
            XCTAssertTrue(message.contains("Duplicate key 'name'"))
        }
    }

    func testOversizedDocumentRejected() {
        var lines = ["proxies:"]
        for index in 0..<20000 {
            lines.append("  - name: P\(index)\n    type: socks5\n    server: 192.0.2.1\n    port: 1080")
        }
        let oversized = lines.joined(separator: "\n")
        XCTAssertGreaterThan(oversized.utf8.count, YAMLLimits.maxDocumentBytes)
        XCTAssertThrowsError(try YAMLParser.parse(oversized)) { error in
            guard case YAMLParsingError.invalidStructure(let line, let message) = error else {
                return XCTFail("Expected invalidStructure, got \(error)")
            }
            XCTAssertEqual(line, 1)
            XCTAssertTrue(message.contains("byte limit"))
        }
    }

    func testOversizedLineRejected() {
        let padding = String(repeating: "x", count: YAMLLimits.maxLineLength + 1)
        let yamlContent = "proxies:\n  - name: \(padding)\n    type: socks5\n    server: 192.0.2.1\n    port: 1080\n"
        XCTAssertThrowsError(try YAMLParser.parse(yamlContent)) { error in
            guard case YAMLParsingError.invalidStructure(let line, let message) = error else {
                return XCTFail("Expected invalidStructure, got \(error)")
            }
            XCTAssertEqual(line, 2)
            XCTAssertTrue(message.contains("character limit"))
        }
    }

    func testProxyCountLimitEnforced() {
        var lines = ["proxies:"]
        for index in 0..<(YAMLLimits.maxProxies + 10) {
            lines.append("  - name: P\(index)")
            lines.append("    type: socks5")
            lines.append("    server: 192.0.2.1")
            lines.append("    port: 1080")
        }
        XCTAssertThrowsError(try YAMLParser.parse(lines.joined(separator: "\n"))) { error in
            guard case YAMLParsingError.validation(let issues) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.reason.contains("Too many proxies") })
        }
    }

    func testRuleCountLimitEnforced() {
        var lines = ["proxies:"]
        lines.append("  - name: A")
        lines.append("    type: socks5")
        lines.append("    server: 192.0.2.1")
        lines.append("    port: 1080")
        lines.append("rules:")
        for index in 0..<(YAMLLimits.maxRules + 10) {
            lines.append("  - DOMAIN,example\(index).com,DIRECT")
        }
        XCTAssertThrowsError(try YAMLParser.parse(lines.joined(separator: "\n"))) { error in
            guard case YAMLParsingError.validation(let issues) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.reason.contains("Too many rules") })
        }
    }

    func testDuplicateKeysStillAllowValidConfig() throws {
        // Regression: the duplicate-key rejection must not break normal configs.
        let yamlContent = """
        proxies:
          - name: "Server-1"
            type: socks5
            server: 192.0.2.10
            port: 1080
        rules:
          - MATCH,DIRECT
        """
        let config = try YAMLParser.parse(yamlContent)
        XCTAssertEqual(config.proxies.count, 1)
    }
}
