import XCTest
@testable import KZTunnelCore

final class ValidationTests: XCTestCase {

    func testIPAddresses() {
        XCTAssertTrue(Validation.isIPv4("192.168.1.1"))
        XCTAssertFalse(Validation.isIPv4("192.168.1.256"))
        XCTAssertFalse(Validation.isIPv4("192.168.1"))
        XCTAssertTrue(Validation.isIPv6("2001:db8::1"))
        XCTAssertFalse(Validation.isIPv6("2001:zz8::1"))
    }

    func testCIDR() {
        XCTAssertTrue(Validation.isCIDR("10.0.0.0/8"))
        XCTAssertTrue(Validation.isCIDR("5.35.96.12"))
        XCTAssertTrue(Validation.isCIDR("2001:db8::/32"))
        XCTAssertFalse(Validation.isCIDR("10.0.0.0/33"))
        XCTAssertFalse(Validation.isCIDR("10.0.0.0/abc"))
        XCTAssertFalse(Validation.isCIDR("kaspi.kz"))
    }

    func testNormalizeCIDR() {
        XCTAssertEqual(Validation.normalizeCIDR("5.35.96.12"), "5.35.96.12/32")
        XCTAssertEqual(Validation.normalizeCIDR(" 10.0.0.0/8 "), "10.0.0.0/8")
        XCTAssertEqual(Validation.normalizeCIDR("2001:db8::1"), "2001:db8::1/128")
        XCTAssertNil(Validation.normalizeCIDR("не адрес"))
    }

    func testDomains() {
        XCTAssertTrue(Validation.isDomain("kaspi.kz"))
        XCTAssertTrue(Validation.isDomain("seller.wildberries.ru"))
        XCTAssertFalse(Validation.isDomain("kaspi"))
        XCTAssertFalse(Validation.isDomain("-kaspi.kz"))
        XCTAssertFalse(Validation.isDomain("kaspi..kz"))
        XCTAssertFalse(Validation.isDomain("kaspi.kz/path"))
        XCTAssertFalse(Validation.isDomain(""))
    }

    func testWireGuardKeys() {
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        XCTAssertTrue(Validation.isWireGuardKey(key))
        XCTAssertFalse(Validation.isWireGuardKey("короткий"))
        XCTAssertFalse(Validation.isWireGuardKey(Data(repeating: 7, count: 16).base64EncodedString()))
    }

    func testEndpoints() {
        XCTAssertEqual(Validation.splitEndpoint("91.201.1.1:51820")?.port, 51820)
        XCTAssertEqual(Validation.splitEndpoint("vpn.example.kz:51820")?.host, "vpn.example.kz")
        XCTAssertEqual(Validation.splitEndpoint("[2001:db8::1]:51820")?.host, "2001:db8::1")
        XCTAssertNil(Validation.splitEndpoint("91.201.1.1"))
        XCTAssertNil(Validation.splitEndpoint("91.201.1.1:99999"))
    }

    func testRuleErrors() {
        XCTAssertNil(Validation.ruleError(kind: .domain, value: "kaspi.kz"))
        XCTAssertNotNil(Validation.ruleError(kind: .domain, value: "10.0.0.0/8"))
        XCTAssertNil(Validation.ruleError(kind: .cidr, value: "10.0.0.0/8"))
        XCTAssertNotNil(Validation.ruleError(kind: .cidr, value: "kaspi.kz"))
        XCTAssertNotNil(Validation.ruleError(kind: .cidr, value: "   "))
    }
}
