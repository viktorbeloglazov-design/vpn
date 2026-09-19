import XCTest
@testable import KZTunnelCore

final class WireGuardConfigTests: XCTestCase {

    private let serverKey = Data(repeating: 1, count: 32).base64EncodedString()
    private let clientKey = Data(repeating: 2, count: 32).base64EncodedString()
    private let psk = Data(repeating: 3, count: 32).base64EncodedString()

    private var sampleConfig: String {
        """
        [Interface]
        PrivateKey = \(clientKey)
        Address = 10.8.0.2/32
        DNS = 1.1.1.1, 8.8.8.8
        MTU = 1380

        [Peer]
        PublicKey = \(serverKey)
        PresharedKey = \(psk)
        Endpoint = 91.201.1.1:51820   # сервер в Алматы
        AllowedIPs = 0.0.0.0/0
        PersistentKeepalive = 25
        """
    }

    func testParse() throws {
        let server = try WireGuardConfig.parse(sampleConfig, name: "KZ-Алматы")
        XCTAssertEqual(server.name, "KZ-Алматы")
        XCTAssertEqual(server.privateKey, clientKey)
        XCTAssertEqual(server.publicKey, serverKey)
        XCTAssertEqual(server.presharedKey, psk)
        XCTAssertEqual(server.endpoint, "91.201.1.1:51820")
        XCTAssertEqual(server.addresses, ["10.8.0.2/32"])
        XCTAssertEqual(server.dns, ["1.1.1.1", "8.8.8.8"])
        XCTAssertEqual(server.mtu, 1380)
        XCTAssertEqual(server.persistentKeepalive, 25)
        XCTAssertNil(server.validationError)
    }

    func testParseRejectsIncomplete() {
        XCTAssertThrowsError(try WireGuardConfig.parse("[Interface]\nAddress = 10.8.0.2/32"))
        XCTAssertThrowsError(try WireGuardConfig.parse("просто текст"))
    }

    func testRender() throws {
        let server = try WireGuardConfig.parse(sampleConfig)
        let withDNS = WireGuardConfig.render(server: server,
                                             allowedIPs: ["0.0.0.0/0"],
                                             includeDNS: true)
        XCTAssertTrue(withDNS.contains("DNS = 1.1.1.1, 8.8.8.8"))
        XCTAssertTrue(withDNS.contains("AllowedIPs = 0.0.0.0/0"))
        XCTAssertTrue(withDNS.contains("PresharedKey = \(psk)"))

        let withoutDNS = WireGuardConfig.render(server: server,
                                                allowedIPs: ["92.46.0.0/16", "5.35.96.12/32"],
                                                includeDNS: false)
        XCTAssertFalse(withoutDNS.contains("DNS ="))
        XCTAssertTrue(withoutDNS.contains("AllowedIPs = 92.46.0.0/16, 5.35.96.12/32"))
    }

    func testRoundTripThroughRenderAndParse() throws {
        let server = try WireGuardConfig.parse(sampleConfig)
        let rendered = WireGuardConfig.render(server: server,
                                              allowedIPs: ["0.0.0.0/0"],
                                              includeDNS: true)
        let reparsed = try WireGuardConfig.parse(rendered)
        XCTAssertEqual(reparsed.publicKey, server.publicKey)
        XCTAssertEqual(reparsed.addresses, server.addresses)
        XCTAssertEqual(reparsed.mtu, server.mtu)
    }

    func testSplitList() {
        XCTAssertEqual(WireGuardConfig.splitList("1.1.1.1, 8.8.8.8"), ["1.1.1.1", "8.8.8.8"])
        XCTAssertEqual(WireGuardConfig.splitList("  "), [])
    }
}
