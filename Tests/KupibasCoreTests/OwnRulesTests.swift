import XCTest
@testable import KupibasCore

/// Поле «Свои сайты через VPN»: что человек впишет и что из этого выйдет.
final class OwnRulesTests: XCTestCase {

    func testИмяСайтаСтановитсяПравилом() {
        let rules = OwnRules.parse("example.com")

        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.kind, .domain)
        XCTAssertEqual(rules.first?.value, "example.com")
    }

    func testАдресСетиСтановитсяПравилом() {
        let rules = OwnRules.parse("203.0.113.0/24")

        XCTAssertEqual(rules.first?.kind, .cidr)
        XCTAssertEqual(rules.first?.value, "203.0.113.0/24")
    }

    func testОдиночныйАдресТожеПринимается() {
        XCTAssertEqual(OwnRules.parse("198.51.100.7").first?.value, "198.51.100.7/32")
    }

    func testКаждоеПравилоСоСвоейСтроки() {
        let rules = OwnRules.parse("""
            example.com
            another.org
            203.0.113.0/24
            """)

        XCTAssertEqual(rules.count, 3)
    }

    func testЗапятыеТожеРазделяют() {
        // Человек вставит список через запятую — это не повод ругаться.
        XCTAssertEqual(OwnRules.parse("example.com, another.org").count, 2)
    }

    // MARK: - Терпимость к тому, как человек пишет

    func testСсылкуЦеликомПонимаем() {
        // Самое частое: скопировал из адресной строки браузера.
        XCTAssertEqual(OwnRules.parse("https://example.com/page?a=1").first?.value,
                       "example.com")
        XCTAssertEqual(OwnRules.parse("http://www.example.com/").first?.value,
                       "www.example.com")
    }

    func testПортОтбрасывается() {
        // Маршрут прокладывается до узла, а не до порта.
        XCTAssertEqual(OwnRules.parse("example.com:8443").first?.value, "example.com")
    }

    func testЛишниеПробелыИПустыеСтрокиНеМешают() {
        let rules = OwnRules.parse("""

              example.com

            another.org
            """)

        XCTAssertEqual(rules.count, 2)
    }

    func testЗаглавныеБуквыПриводятсяКМалым() {
        XCTAssertEqual(OwnRules.parse("Example.COM").first?.value, "example.com")
    }

    func testПовторыНеДублируются() {
        let rules = OwnRules.parse("""
            example.com
            EXAMPLE.COM
            https://example.com/page
            """)

        XCTAssertEqual(rules.count, 1, "одно и то же имя не должно попасть трижды")
    }

    func testСтрокаСРешёткойЭтоЗаметкаЧеловека() {
        let rules = OwnRules.parse("""
            # мои сайты
            example.com
            """)

        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.value, "example.com")
    }

    // MARK: - Непонятное

    func testНепонятноеНеПроглатываетсяМолча() {
        // Опечатку надо показать, а не потерять.
        let text = """
            example.com
            это не адрес
            """

        XCTAssertEqual(OwnRules.parse(text).count, 1)
        XCTAssertEqual(OwnRules.unreadable(text), ["это не адрес"])
    }

    func testНаПравильномТекстеЖалобНет() {
        XCTAssertTrue(OwnRules.unreadable("example.com\n203.0.113.0/24").isEmpty)
    }

    func testПустоеПолеЭтоНеОшибка() {
        XCTAssertTrue(OwnRules.parse("").isEmpty)
        XCTAssertTrue(OwnRules.unreadable("   \n\n  ").isEmpty)
    }

    // MARK: - Туда и обратно

    func testТекстВосстанавливаетсяДляПоля() {
        let text = "example.com\n203.0.113.0/24"
        XCTAssertEqual(OwnRules.text(from: OwnRules.parse(text)), text)
    }

    func testСвоиПравилаДоходятДоТуннеля() {
        // Самое важное: вписанное человеком должно пойти через VPN.
        var config = TunnelConfig()
        config.rules = OwnRules.parse("my-service.example\n203.0.113.0/24")

        let pinned = config.pinned()

        XCTAssertEqual(pinned.effectiveMode, .include)
        XCTAssertTrue(pinned.activeRules.contains { $0.value == "my-service.example" })
        XCTAssertTrue(pinned.activeRules.contains { $0.value == "203.0.113.0/24" })
    }
}
