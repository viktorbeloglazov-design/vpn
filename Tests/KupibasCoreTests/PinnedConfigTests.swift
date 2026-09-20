import XCTest
@testable import KupibasCore

/// Маршрутизация зашита: переключателей для неё в программе больше нет,
/// поэтому настройки обязаны приводиться к одному и тому же виду — иначе
/// значение, сохранённое прежней версией, останется навсегда.
final class PinnedConfigTests: XCTestCase {

    func testFreshConfigIsAlreadyPinned() {
        let fresh = TunnelConfig()
        XCTAssertEqual(fresh, fresh.pinned(), "заводские настройки не должны ничего менять")
        XCTAssertTrue(fresh.mainFilter, "обход блокировок работает всегда")
        XCTAssertFalse(fresh.fullTunnel, "весь трафик в туннель не загоняем")
        XCTAssertEqual(fresh.effectiveMode, .exclude)
    }

    func testOldSettingsAreBroughtBack() {
        // Так мог выглядеть файл, сохранённый версией с переключателями.
        var stored = TunnelConfig()
        stored.fullTunnel = true
        stored.mainFilter = false
        stored.mode = .include
        stored.rules = [RoutingRule(kind: .domain, value: "example.com")]
        stored.options.useTunnelDNS = false
        stored.options.disableIPv6 = false
        stored.options.autoReconnect = false

        let pinned = stored.pinned()

        XCTAssertFalse(pinned.fullTunnel)
        XCTAssertTrue(pinned.mainFilter)
        XCTAssertEqual(pinned.mode, .exclude)
        XCTAssertEqual(pinned.effectiveMode, .exclude)
        XCTAssertTrue(pinned.rules.isEmpty, "свои правила больше не задаются")
        XCTAssertTrue(pinned.options.useTunnelDNS, "DNS из ключа используется всегда")
        XCTAssertTrue(pinned.options.disableIPv6, "IPv6 наружу не выпускаем")
        XCTAssertTrue(pinned.options.autoReconnect, "оборванную связь чиним всегда")
    }

    func testTheOnlySwitchSurvives() {
        // Рабочие ресурсы — единственное, что человек выбирает сам.
        var off = TunnelConfig()
        off.workFilter = false
        XCTAssertFalse(off.pinned().workFilter)

        var on = TunnelConfig()
        on.workFilter = true
        XCTAssertTrue(on.pinned().workFilter)
    }

    func testMTUStaysAsChosen() {
        // MTU к маршрутизации не относится: его иногда приходится менять руками.
        var config = TunnelConfig()
        config.options.mtu = 1280
        XCTAssertEqual(config.pinned().options.mtu, 1280)
    }

    func testMTUOverrideReachesTheTunnel() {
        let server = ServerConfig(endpoint: "91.201.1.1:51820",
                                  publicKey: Data(repeating: 1, count: 32).base64EncodedString(),
                                  privateKey: Data(repeating: 2, count: 32).base64EncodedString(),
                                  addresses: ["10.8.0.2/32"],
                                  mtu: 1420)

        let fromKey = WireGuardConfig.render(server: server, allowedIPs: ["0.0.0.0/0"], includeDNS: false)
        XCTAssertTrue(fromKey.contains("MTU = 1420"))

        let overridden = WireGuardConfig.render(server: server,
                                                allowedIPs: ["0.0.0.0/0"],
                                                includeDNS: false,
                                                mtuOverride: 1280)
        XCTAssertTrue(overridden.contains("MTU = 1280"), "выбранный размер пакета должен доходить до туннеля")

        // Смена MTU обязана пересоздавать туннель, иначе она ничего не изменит.
        var base = TunnelConfig(server: server)
        let before = base.restartSignature
        base.options.mtu = 1280
        XCTAssertNotEqual(before, base.restartSignature)
    }
}
