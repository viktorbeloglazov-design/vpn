import XCTest
@testable import KupibasCore

/// Список сервисов, которые идут через VPN, и то, что идёт мимо.
final class VpnServicesTests: XCTestCase {

    func testВСпискеЕстьВсёЧтоПросили() {
        let названия = VpnServices.titles

        for нужное in ["WhatsApp", "Instagram", "Telegram", "YouTube"] {
            XCTAssertTrue(названия.contains(нужное), "Нет \(нужное)")
        }
        for ии in ["ChatGPT", "Claude", "Gemini", "Perplexity", "Grok", "DeepSeek"] {
            XCTAssertTrue(названия.contains(ии), "Нет \(ии)")
        }
    }

    func testСетиПосредниковВТуннельНеУходят() {
        // Главное правило списка. За Cloudflare стоят десятки тысяч чужих
        // сайтов, включая российские: заверни их в туннель — и они поедут
        // через Казахстан вместо прямого пути.
        let сети = VpnServices.services.flatMap(\.networks)

        for чужая in VpnServices.cloudflare {
            XCTAssertFalse(сети.contains(чужая),
                           "Сеть Cloudflare \(чужая) не должна идти в туннель")
        }
    }

    func testУСервисовНаCloudflareНетСвоихСетей() {
        // У них адреса берутся только из DNS — по-другому нельзя.
        let наCloudflare = ["ChatGPT", "Perplexity", "Grok", "DeepSeek",
                            "Mistral", "Midjourney", "Suno"]

        for название in наCloudflare {
            let сервис = VpnServices.services.first { $0.title == название }
            XCTAssertNotNil(сервис, "Нет сервиса \(название)")
            XCTAssertTrue(сервис!.networks.isEmpty,
                          "\(название) живёт на Cloudflare — своих сетей у него быть не может")
            XCTAssertFalse(сервис!.domains.isEmpty, "\(название) без имён не заработает")
        }
    }

    func testВсеСетиРазбираются() {
        for сеть in VpnServices.services.flatMap(\.networks) {
            XCTAssertNotNil(Cidr.parse(сеть), "Не разбирается: \(сеть)")
        }
    }

    func testВсеИменаПохожиНаИмена() {
        for имя in VpnServices.services.flatMap(\.domains) {
            XCTAssertTrue(Validation.isDomain(имя), "Не имя: \(имя)")
        }
    }

    func testМедиаМессенджеровПеречисленоОтдельно() {
        // Отсюда жалобы «сообщения ходят, а фото не грузятся»: медиа
        // отдаётся с других имён, чем сам сервис.
        let whatsapp = VpnServices.services.first { $0.title == "WhatsApp" }!
        XCTAssertTrue(whatsapp.domains.contains("mmg.whatsapp.net"))
        XCTAssertTrue(whatsapp.domains.contains("media.whatsapp.net"))

        let instagram = VpnServices.services.first { $0.title == "Instagram" }!
        XCTAssertTrue(instagram.domains.contains("scontent.cdninstagram.com"))
    }

    // MARK: - Проверка ответа DNS

    func testАдресСервисаПринимается() {
        let адрес = Cidr.parse("157.240.1.1")!      // сеть Meta
        XCTAssertTrue(VpnServices.isServiceAddress(адрес))
    }

    func testРоссийскаяЗаглушкаОтвергается() {
        // На заблокированное имя провайдер отвечает адресом своей
        // заглушки: адрес живой и публичный, но чужой.
        let заглушка = Cidr.parse("95.213.0.1")!
        XCTAssertFalse(VpnServices.isServiceAddress(заглушка))
    }

    func testВнутренниеАдресаОтвергаются() {
        for внутренний in ["127.0.0.1", "10.0.0.5", "192.168.1.1", "0.0.0.0"] {
            XCTAssertFalse(VpnServices.isServiceAddress(Cidr.parse(внутренний)!),
                           "\(внутренний) не должен считаться адресом сервиса")
        }
    }

    // MARK: - Правила

    func testПравилаСобираютсяИзСетейИИмён() {
        let правила = VpnServices.rules()

        XCTAssertTrue(правила.contains { $0.kind == .cidr && $0.value == "157.240.0.0/16" })
        XCTAssertTrue(правила.contains { $0.kind == .domain && $0.value == "chatgpt.com" })
        XCTAssertTrue(правила.allSatisfy { $0.enabled })
        XCTAssertTrue(правила.allSatisfy { !$0.note.isEmpty },
                      "У каждого правила должно быть видно, чей он")
    }

    func testЗашитыеПравилаОтличимыОтСвоих() {
        // По этому признаку свои правила человека не теряются при
        // обновлении зашитого списка.
        XCTAssertTrue(VpnServices.rules().allSatisfy {
            $0.id.hasPrefix("сеть:") || $0.id.hasPrefix("имя:")
        })
    }
}
