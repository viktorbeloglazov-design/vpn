import XCTest
@testable import KupibasCore

/// Разбор того, чем делится Amnezia: ссылка vpn:// и QR-код с ней же.
final class SharedLinkTests: XCTestCase {

    private let sample = """
    [Interface]
    PrivateKey = qJf1n1eK1mVvVYQfLJcQ0h0m3kq3Y0O0kQ1Zz1cK1mA=
    Address = 10.8.0.2/32
    DNS = 1.1.1.1

    [Peer]
    PublicKey = mJf1n1eK1mVvVYQfLJcQ0h0m3kq3Y0O0kQ1Zz1cK1mA=
    Endpoint = 91.201.1.1:51820
    AllowedIPs = 0.0.0.0/0
    """

    func testPlainConfigPassesThrough() {
        let config = SharedLink.extractConfig(sample)
        XCTAssertNotNil(config)
        XCTAssertTrue(config!.hasPrefix("[Interface]"))
        XCTAssertTrue(config!.contains("Endpoint = 91.201.1.1:51820"))
    }

    func testLinkWithJsonInside() {
        // Так свёрток выглядит внутри: конфигурация лежит строкой в JSON.
        let escaped = sample
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let json = "{\"defaultContainer\":\"amnezia-awg\",\"awg_config_data\":\"\(escaped)\"}"
        let payload = Data(json.utf8).base64EncodedString()

        let config = SharedLink.extractConfig("vpn://" + payload)
        XCTAssertNotNil(config, "конфигурация из ссылки не развернулась")
        XCTAssertTrue(config!.hasPrefix("[Interface]"))
        XCTAssertTrue(config!.contains("AllowedIPs = 0.0.0.0/0"))
        XCTAssertFalse(config!.contains("\\n"), "переводы строк остались экранированными")
    }

    func testBase64UrlAlphabetIsAccepted() {
        let json = "{\"config\":\"[Interface]\\nPrivateKey = A\\n[Peer]\\nEndpoint = 1.2.3.4:5\"}"
        let payload = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        XCTAssertNotNil(SharedLink.extractConfig("vpn://" + payload))
    }

    func testGarbageIsRejected() {
        XCTAssertNil(SharedLink.extractConfig(""))
        XCTAssertNil(SharedLink.extractConfig("vpn://не-ссылка"))
        XCTAssertNil(SharedLink.extractConfig("https://example.com/page"))
    }

    func testLinkIsRecognised() {
        XCTAssertTrue(SharedLink.looksLikeLink("vpn://AAAA"))
        XCTAssertTrue(SharedLink.looksLikeLink(" amnezia://AAAA "))
        XCTAssertFalse(SharedLink.looksLikeLink("[Interface]"))
    }
}
