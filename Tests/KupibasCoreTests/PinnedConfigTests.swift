import XCTest
@testable import KupibasCore

/// Маршрутизация зашита: переключателей для неё в программе больше нет,
/// поэтому настройки обязаны приводиться к одному и тому же виду — иначе
/// значение, сохранённое прежней версией, останется навсегда.
final class PinnedConfigTests: XCTestCase {

    func testЧерезVPNИдётТолькоСписокСервисов() {
        let fresh = TunnelConfig().pinned()

        XCTAssertEqual(fresh.effectiveMode, .include,
                       "через VPN идёт только перечисленное, остальное напрямую")
        XCTAssertFalse(fresh.fullTunnel, "весь трафик в туннель не загоняем")
        XCTAssertFalse(fresh.mainFilter, "прежняя модель «всё, кроме РФ» больше не работает")
    }

    func testЗаводскиеНастройкиУжеЗакреплены() {
        let fresh = TunnelConfig()
        XCTAssertEqual(fresh.pinned().effectiveMode, fresh.effectiveMode,
                       "заводские настройки не должны ничего менять")
    }

    func testНастройкиПрошлойВерсииПереводятсяНаНовуюМодель() {
        // Так выглядел файл, записанный версией с моделью «всё, кроме РФ».
        var stored = TunnelConfig()
        stored.fullTunnel = true
        stored.mainFilter = true
        stored.mode = .exclude
        stored.options.useTunnelDNS = false
        stored.options.disableIPv6 = false
        stored.options.autoReconnect = false

        let pinned = stored.pinned()

        XCTAssertFalse(pinned.fullTunnel)
        XCTAssertFalse(pinned.mainFilter)
        XCTAssertEqual(pinned.effectiveMode, .include)
        XCTAssertTrue(pinned.options.useTunnelDNS)
        XCTAssertTrue(pinned.options.disableIPv6)
        XCTAssertTrue(pinned.options.autoReconnect, "оборванную связь чиним всегда")
    }

    func testЗашитыйСписокПопадаетВПравила() {
        let rules = TunnelConfig().pinned().rules

        XCTAssertTrue(rules.contains { $0.kind == .domain && $0.value == "chatgpt.com" })
        XCTAssertTrue(rules.contains { $0.kind == .domain && $0.value == "web.whatsapp.com" })
        XCTAssertTrue(rules.contains { $0.kind == .domain && $0.value == "instagram.com" })
        XCTAssertTrue(rules.contains { $0.kind == .cidr && $0.value == "91.108.56.0/22" })
    }

    func testСвоиПравилаЧеловекаСохраняются() {
        // Их человек вписывает сам, и обновление зашитого списка не должно
        // их терять.
        var config = TunnelConfig()
        config.rules = [RoutingRule(kind: .domain, value: "my-site.example", note: "своё")]

        let pinned = config.pinned()

        XCTAssertTrue(pinned.rules.contains { $0.value == "my-site.example" },
                      "добавленное вручную должно остаться")
        XCTAssertEqual(pinned.ownRules.count, 1)
        XCTAssertEqual(pinned.ownRules.first?.value, "my-site.example")
    }

    func testСвоиПравилаНеДублируютсяПриПовторномЗакреплении() {
        // pinned() вызывается при каждом чтении настроек: список не должен
        // расти с каждым разом.
        var config = TunnelConfig()
        config.rules = [RoutingRule(kind: .domain, value: "my-site.example")]

        let один = config.pinned()
        let два = один.pinned()
        let три = два.pinned()

        XCTAssertEqual(один.rules.count, три.rules.count, "список не должен расти")
        XCTAssertEqual(три.ownRules.count, 1)
    }

    func testЗашитыеПравилаНеСчитаютсяСвоими() {
        XCTAssertTrue(TunnelConfig().pinned().ownRules.isEmpty,
                      "без добавлений человека своих правил быть не должно")
    }

    func testРабочиеРесурсыИдутЧерезVPNПриВключённомПереключателе() {
        // В прежней модели они попадали в туннель тем, что вычитались
        // из российской зоны. В новой вычитать не из чего — их нужно
        // добавить в список, иначе переключатель ничего не значит.
        var config = TunnelConfig()
        config.workFilter = true

        let rules = config.pinned().activeRules
        for host in WorkFilter.hosts {
            XCTAssertTrue(rules.contains { $0.value == host },
                          "рабочий адрес \(host) должен идти через VPN")
        }
    }

    func testПриВыключенномПереключателеРабочихПравилНет() {
        var config = TunnelConfig()
        config.workFilter = false

        let rules = config.pinned().activeRules
        for host in WorkFilter.hosts {
            XCTAssertFalse(rules.contains { $0.value == host },
                           "выключенный переключатель не должен ничего добавлять")
        }
    }

    func testРабочиеПравилаНеСчитаютсяСвоими() {
        // Иначе они дублировались бы при каждом закреплении настроек.
        var config = TunnelConfig()
        config.workFilter = true

        let один = config.pinned()
        let три = один.pinned().pinned()

        XCTAssertTrue(один.ownRules.isEmpty)
        XCTAssertEqual(один.rules.count, три.rules.count, "список не должен расти")
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
