import XCTest
@testable import KupibasCore

/// Туннель поднимается без wg-quick — проверяем то, что этому нужно.
///
/// wg-quick на macOS требует bash 4+, а система поставляет 3.2: скрипт
/// останавливается на «Version mismatch», и туннель не поднимается вовсе.
/// Теперь службa делает его работу сама, и части этой работы должны быть
/// ровно такими, как ждёт система.
final class TunnelSetupTests: XCTestCase {

    private func makeServer() -> ServerConfig {
        ServerConfig(name: "KZ",
                     endpoint: "77.240.39.23:31984",
                     publicKey: Data(repeating: 1, count: 32).base64EncodedString(),
                     presharedKey: Data(repeating: 3, count: 32).base64EncodedString(),
                     privateKey: Data(repeating: 2, count: 32).base64EncodedString(),
                     addresses: ["10.8.1.13/32"],
                     dns: ["1.1.1.1", "1.0.0.1"],
                     mtu: 1420,
                     amneziaParams: ["jc": "4", "s1": "15", "h1": "1234567890"])
    }

    func testSetConfHasNoWgQuickKeys() {
        // Утилита управления понимает только ключи самого туннеля: Address,
        // DNS и MTU она считает ошибкой и ничего не настроит.
        let text = WireGuardConfig.renderForSetConf(server: makeServer(), allowedIPs: ["0.0.0.0/0"])

        XCTAssertFalse(text.contains("Address"), "Address утилита не примет")
        XCTAssertFalse(text.contains("DNS"), "DNS утилита не примет")
        XCTAssertFalse(text.contains("MTU"), "MTU утилита не примет")

        XCTAssertTrue(text.contains("PrivateKey = "))
        XCTAssertTrue(text.contains("PublicKey = "))
        XCTAssertTrue(text.contains("PresharedKey = "))
        XCTAssertTrue(text.contains("Endpoint = 77.240.39.23:31984"))
        XCTAssertTrue(text.contains("AllowedIPs = 0.0.0.0/0"))
        XCTAssertTrue(text.contains("PersistentKeepalive = 25"))
    }

    func testSetConfKeepsMaskingParameters() {
        // Потеряется хоть один — сервер Amnezia не ответит на рукопожатие.
        let text = WireGuardConfig.renderForSetConf(server: makeServer(), allowedIPs: ["0.0.0.0/0"])
        XCTAssertTrue(text.contains("Jc = 4"))
        XCTAssertTrue(text.contains("S1 = 15"))
        XCTAssertTrue(text.contains("H1 = 1234567890"))
    }

    func testFullTunnelIsSplitInTwoHalves() {
        // 0.0.0.0/0 поспорил бы с маршрутом по умолчанию, и настоящий канал
        // пропал бы — а через него уходит сам зашифрованный трафик.
        XCTAssertEqual(WireGuardConfig.routeDestinations(for: ["0.0.0.0/0"]),
                       ["0.0.0.0/1", "128.0.0.0/1"])
        XCTAssertEqual(WireGuardConfig.routeDestinations(for: ["::/0"]),
                       ["::/1", "8000::/1"])
        XCTAssertEqual(WireGuardConfig.routeDestinations(for: ["0.0.0.0/0", "::/0"]),
                       ["0.0.0.0/1", "128.0.0.0/1", "::/1", "8000::/1"])
    }

    func testOrdinarySubnetsAreLeftAlone() {
        XCTAssertEqual(WireGuardConfig.routeDestinations(for: ["10.0.0.0/8", "192.168.1.0/24"]),
                       ["10.0.0.0/8", "192.168.1.0/24"])
    }

    func testEndpointHostIsKnownForTheBypassRoute() {
        // Без маршрута до сервера мимо туннеля туннель замкнётся сам на себя.
        XCTAssertEqual(makeServer().endpointHost, "77.240.39.23")
    }
}
