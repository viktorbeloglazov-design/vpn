import XCTest
@testable import KupibasCore

/// Ключи X-Ray. Все адреса и идентификаторы выдуманы: репозиторий публичный.
final class XrayLinkTests: XCTestCase {

    private let uuid = "00000000-0000-4000-8000-000000000000"

    private var reality: String {
        "vless://\(uuid)@203.0.113.10:443?encryption=none&flow=xtls-rprx-vision&security=reality"
            + "&sni=www.example.com&fp=chrome&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
            + "&sid=0123abcd&spx=%2F&type=tcp&headerType=none#QP%20VPN%20KZ"
    }

    func testVlessRealityРазбирается() throws {
        let link = try XrayLink.parse(reality)
        XCTAssertEqual(link.kind, .vless)
        XCTAssertEqual(link.host, "203.0.113.10")
        XCTAssertEqual(link.port, 443)
        XCTAssertEqual(link.secret, uuid)
        XCTAssertEqual(link.flow, "xtls-rprx-vision")
        XCTAssertEqual(link.security, "reality")
        XCTAssertEqual(link.sni, "www.example.com")
        XCTAssertEqual(link.shortId, "0123abcd")
        XCTAssertEqual(link.spiderX, "/")
        XCTAssertEqual(link.name, "QP VPN KZ")
        XCTAssertEqual(link.endpoint, "203.0.113.10:443")
        XCTAssertEqual(link.title, "X-Ray (VLESS Reality)")
    }

    func testКлючНаходитсяВнутриПисьма() throws {
        let letter = "Здравствуйте! Ваш ключ:\n\n  \(reality)  \n\nВставьте его в приложение."
        XCTAssertTrue(XrayLink.looksLikeLink(letter))
        XCTAssertEqual(try XrayLink.parse(letter).host, "203.0.113.10")
    }

    func testRealityБезКлючаНеПринимается() {
        let broken = "vless://\(uuid)@203.0.113.10:443?security=reality&sni=www.example.com"
        XCTAssertThrowsError(try XrayLink.parse(broken))
    }

    func testБезПортаНеПринимается() {
        XCTAssertThrowsError(try XrayLink.parse("vless://\(uuid)@203.0.113.10?security=none"))
    }

    func testВебсокетСTLS() throws {
        let link = try XrayLink.parse("vless://\(uuid)@vpn.example.com:8443?type=ws&security=tls"
            + "&path=%2Fws&host=cdn.example.com&sni=vpn.example.com&alpn=h2,http/1.1")
        XCTAssertEqual(link.network, "ws")
        XCTAssertEqual(link.path, "/ws")
        XCTAssertEqual(link.hostHeader, "cdn.example.com")
        XCTAssertEqual(link.alpn, ["h2", "http/1.1"])
    }

    func testТроян() throws {
        let link = try XrayLink.parse("trojan://secret-pass@vpn.example.com:443?sni=vpn.example.com#Trojan")
        XCTAssertEqual(link.kind, .trojan)
        XCTAssertEqual(link.secret, "secret-pass")
        XCTAssertEqual(link.security, "tls", "у Trojan TLS по умолчанию")
    }

    func testVmessИзBase64() throws {
        let json = """
        {"v":"2","ps":"VMess","add":"203.0.113.20","port":"443","id":"\(uuid)","aid":"0",
         "scy":"auto","net":"ws","type":"none","host":"cdn.example.com","path":"/v","tls":"tls","sni":"cdn.example.com"}
        """
        let link = try XrayLink.parse("vmess://" + Data(json.utf8).base64EncodedString())
        XCTAssertEqual(link.kind, .vmess)
        XCTAssertEqual(link.port, 443)
        XCTAssertEqual(link.network, "ws")
        XCTAssertEqual(link.security, "tls")
    }

    func testShadowsocksОбаВида() throws {
        let userInfo = Data("chacha20-ietf-poly1305:pass123".utf8).base64EncodedString()
        let sip002 = try XrayLink.parse("ss://\(userInfo)@203.0.113.30:8388#SS")
        XCTAssertEqual(sip002.method, "chacha20-ietf-poly1305")
        XCTAssertEqual(sip002.secret, "pass123")
        XCTAssertEqual(sip002.port, 8388)

        let whole = Data("aes-256-gcm:pass456@203.0.113.31:8389".utf8).base64EncodedString()
        let legacy = try XrayLink.parse("ss://\(whole)#Old")
        XCTAssertEqual(legacy.host, "203.0.113.31")
        XCTAssertEqual(legacy.secret, "pass456")
    }

    // MARK: - Настройки xray

    private func json(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testНастройкиXrayДляReality() throws {
        let config = try json(XrayConfig.render(try XrayLink.parse(reality)))

        let inbound = try XCTUnwrap((config["inbounds"] as? [[String: Any]])?.first)
        XCTAssertEqual(inbound["listen"] as? String, "127.0.0.1",
                       "вход только для самого компьютера — иначе им воспользуется любой в сети")
        XCTAssertEqual(inbound["protocol"] as? String, "socks")
        XCTAssertEqual((inbound["settings"] as? [String: Any])?["udp"] as? Bool, true,
                       "без UDP не будет звонков в WhatsApp и Telegram")

        let outbound = try XCTUnwrap((config["outbounds"] as? [[String: Any]])?.first)
        XCTAssertEqual(outbound["protocol"] as? String, "vless")
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        XCTAssertEqual(stream["security"] as? String, "reality")
        let realitySettings = try XCTUnwrap(stream["realitySettings"] as? [String: Any])
        XCTAssertEqual(realitySettings["publicKey"] as? String, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(realitySettings["serverName"] as? String, "www.example.com")

        let vnext = try XCTUnwrap(((outbound["settings"] as? [String: Any])?["vnext"] as? [[String: Any]])?.first)
        let user = try XCTUnwrap((vnext["users"] as? [[String: Any]])?.first)
        XCTAssertEqual(user["flow"] as? String, "xtls-rprx-vision")
        XCTAssertEqual(user["encryption"] as? String, "none")
    }

    // MARK: - Ключ целиком

    func testКлючXRayСтановитсяСервером() throws {
        let server = try KeyImport.parse(reality)
        XCTAssertTrue(server.isXray)
        XCTAssertEqual(server.endpoint, "203.0.113.10:443")
        XCTAssertEqual(server.endpointHost, "203.0.113.10")
        XCTAssertEqual(server.name, "QP VPN KZ")
        XCTAssertNil(server.validationError, "ключу X-Ray не нужны поля WireGuard")
        XCTAssertEqual(server.protocolName, "X-Ray (VLESS Reality)")
    }

    func testПрежнийКлючПоПрежнемуWireGuard() throws {
        let conf = """
        [Interface]
        PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
        Address = 10.8.0.2/32
        [Peer]
        PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=
        Endpoint = 203.0.113.40:51820
        AllowedIPs = 0.0.0.0/0
        """
        let server = try KeyImport.parse(conf)
        XCTAssertFalse(server.isXray)
        XCTAssertEqual(server.endpoint, "203.0.113.40:51820")
    }

    func testСменаКлючаXRayПерезапускаетТуннель() throws {
        var config = TunnelConfig()
        config.server = try KeyImport.parse(reality)
        let before = config.restartSignature
        config.server = try KeyImport.parse(reality.replacingOccurrences(of: "0123abcd", with: "fedc4321"))
        XCTAssertNotEqual(before, config.restartSignature)
    }

    func testКлючСохраняетсяИЧитаетсяОбратно() throws {
        let server = try KeyImport.parse(reality)
        let data = try JSONEncoder().encode(server)
        let back = try JSONDecoder().decode(ServerConfig.self, from: data)
        XCTAssertEqual(back.xrayLink, server.xrayLink)
        XCTAssertTrue(back.isXray)
    }
}
