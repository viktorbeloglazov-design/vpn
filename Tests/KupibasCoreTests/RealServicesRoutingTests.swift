import XCTest
@testable import KupibasCore

/// Живая проверка маршрутизации на настоящих адресах.
///
/// Модель простая: через VPN идёт только список сервисов — мессенджеры,
/// видео, ИИ. Всё остальное идёт напрямую: российские сайты, банки,
/// маркетплейсы, госуслуги, 1С и вообще весь прочий интернет.
///
/// Адреса записаны числами, а не именами: на сборочной машине нет ни
/// интернета, ни DNS, а имя всё равно разрешилось бы в адрес ближайшей
/// сети, а не той, что отвечает человеку.
///
/// Тот же список проверяется в версии для телефона — фильтры обязаны
/// совпадать один в один.
final class RealServicesRoutingTests: XCTestCase {

    /// Сети, которые уходят в туннель, — ровно как считает служба.
    private var tunnelNets: [Ipv4Net] {
        VpnServices.services.flatMap(\.networks).compactMap { Cidr.parse($0) }
    }

    private func goesThroughVPN(_ address: String) -> Bool {
        guard let net = Cidr.parse(address) else { return false }
        return tunnelNets.contains { net.start >= $0.start && Int64(net.start) <= $0.endInclusive }
    }

    // MARK: - Через VPN

    func testСервисыИзСпискаИдутЧерезVPN() {
        let services: [(String, [String])] = [
            // Meta: WhatsApp и Instagram, включая раздачу фото и видео.
            ("WhatsApp", ["157.240.1.1", "31.13.64.35", "179.60.192.1"]),
            ("Instagram", ["157.240.253.174", "31.13.24.1"]),
            ("Instagram, картинки", ["57.144.1.1"]),
            // Telegram — свои сети.
            ("Telegram", ["149.154.167.51", "91.108.56.130", "91.108.4.1"]),
            // Google: YouTube и Gemini.
            ("YouTube", ["142.250.74.14", "172.217.16.78", "216.58.192.1"]),
            ("YouTube, видео", ["173.194.1.1", "74.125.1.1"]),
            ("Gemini", ["142.251.1.1", "209.85.128.1"]),
            // Своя сеть Anthropic.
            ("Claude", ["160.79.104.10", "160.79.105.200"]),
        ]

        for (name, addresses) in services {
            for address in addresses {
                XCTAssertTrue(goesThroughVPN(address),
                              "\(name) (\(address)) должен идти через VPN — иначе сервис останется заблокированным")
            }
        }
    }

    // MARK: - Напрямую

    func testРоссийскиеСервисыИдутНапрямую() {
        let russian: [(String, [String])] = [
            ("МАХ", ["155.212.204.5", "155.212.204.143"]),
            ("Госуслуги", ["213.59.253.7", "212.42.65.4"]),
            ("Налоговая", ["195.208.66.236"]),
            ("Сбербанк", ["84.252.149.206"]),
            ("Т-Банк", ["178.130.128.27"]),
            ("Альфа-Банк", ["217.12.104.100"]),
            ("ВТБ", ["195.242.82.13"]),
            ("ВКонтакте", ["87.240.129.133"]),
            ("Почта Mail.ru", ["185.180.201.1"]),
            ("Яндекс", ["5.255.255.77", "77.88.44.55"]),
            ("Озон", ["185.73.193.68"]),
            ("Wildberries", ["185.62.202.2"]),
            ("Авито", ["176.114.120.24"]),
            ("РЖД", ["212.164.138.120"]),
            ("Аэрофлот", ["195.209.66.33"]),
            ("Ростелеком", ["87.226.162.216"]),
        ]

        for (name, addresses) in russian {
            for address in addresses {
                XCTAssertFalse(goesThroughVPN(address),
                               "\(name) (\(address)) должен идти напрямую — через VPN он может не пустить")
            }
        }
    }

    func testЧужиеСайтыНаCloudflareНеУходятВТуннельЦеликом() {
        // Доказано на живом примере: за Cloudflare стоят и российские
        // сайты. Если завернуть сети Cloudflare в туннель, они поедут
        // через Казахстан вместо прямого пути.
        for address in ["104.18.32.115", "172.64.155.141", "104.21.32.39", "172.67.182.196"] {
            XCTAssertFalse(goesThroughVPN(address),
                           "Сеть Cloudflare (\(address)) не должна уходить в туннель по адресу")
        }
    }

    func testОстальнойИнтернетИдётНапрямую() {
        // Модель именно такая: в туннель — только список, всё прочее мимо.
        let others: [(String, String)] = [
            ("LinkedIn", "13.107.42.14"),
            ("Spotify", "35.186.224.25"),
            ("GitHub Pages", "185.199.108.153"),
            ("Fastly", "151.101.1.140"),
            ("Amazon", "52.95.110.1"),
        ]

        for (name, address) in others {
            XCTAssertFalse(goesThroughVPN(address),
                           "\(name) (\(address)) в списке не числится — должен идти напрямую")
        }
    }

    // MARK: - Сервисы, которых по адресу не поймать

    func testСервисыНаCloudflareПопадаютВТуннельПоИмени() {
        // У ChatGPT и прочих ИИ своих сетей нет: адрес узнаётся у DNS
        // и прокладывается поштучно. Поэтому в списке обязаны быть имена.
        let rules = VpnServices.rules()

        for имя in ["chatgpt.com", "api.openai.com", "perplexity.ai",
                    "grok.com", "chat.deepseek.com"] {
            XCTAssertTrue(rules.contains { $0.kind == .domain && $0.value == имя },
                          "Без имени \(имя) сервис через VPN не пойдёт")
        }
    }
}
