import XCTest
@testable import Tunnexa

final class YAMLParserTests: XCTestCase {
    
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
        
        // Assert groups
        XCTAssertEqual(config.groups.count, 1)
        XCTAssertEqual(config.groups[0].name, "BypassEmpire")
        XCTAssertEqual(config.groups[0].type, .select)
        XCTAssertEqual(config.groups[0].proxies.count, 2)
        XCTAssertEqual(config.groups[0].proxies[0], "Server-1")
        
        // Assert rules
        XCTAssertEqual(config.rules.count, 2)
        XCTAssertEqual(config.rules[0].type, .domainSuffix)
        XCTAssertEqual(config.rules[0].payload, "google.com")
        XCTAssertEqual(config.rules[0].target, "BypassEmpire")
        
        XCTAssertEqual(config.rules[1].type, .match)
        XCTAssertNil(config.rules[1].payload)
        XCTAssertEqual(config.rules[1].target, "BypassEmpire")
    }
    
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
    
    func testCredentialRedaction() {
        let logLine = "Connecting with username=rakib and password=mysecretpassword"
        let redacted = SharedLogging.redactCredentials(logLine)
        
        XCTAssertTrue(redacted.contains("password: [REDACTED]"))
        XCTAssertTrue(redacted.contains("username: [REDACTED]"))
        XCTAssertFalse(redacted.contains("mysecretpassword"))
        XCTAssertFalse(redacted.contains("rakib"))
    }
}
