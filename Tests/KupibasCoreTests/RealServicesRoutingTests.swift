import XCTest
@testable import KupibasCore

/// Живая проверка зашитой маршрутизации на настоящих адресах.
///
/// Переключателей больше нет, поэтому поведение обязано быть одним и тем же
/// у всех: российские сервисы — напрямую, заблокированные — через VPN. Адреса
/// записаны числами, а не именами: на сборке нет ни интернета, ни DNS, а имя
/// всё равно разрешилось бы в адрес ближайшей сети, а не абонентской.
///
/// Тот же список проверяется в версии для телефона — фильтры обязаны
/// совпадать один в один.
final class RealServicesRoutingTests: XCTestCase {

    /// Подсети, которые остаются вне туннеля, — ровно как считает служба.
    private var directZone: [Ipv4Net] {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // KupibasCoreTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // корень
            .appendingPathComponent("Resources/ru_ipv4.txt")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return [] }

        let zone = RuZone.parse(text)
        // Рабочие ресурсы лежат в российской зоне, но мимо туннеля не уходят.
        let work = WorkFilter.hosts.compactMap { Cidr.parse($0) }
        return work.isEmpty ? Cidr.merge(zone) : Cidr.subtract(zone, work)
    }

    private func goesDirect(_ address: String, in nets: [Ipv4Net]) -> Bool {
        guard let net = Cidr.parse(address) else { return false }
        return nets.contains { net.start >= $0.start && Int64(net.start) <= $0.endInclusive }
    }

    func testRussianServicesGoDirect() {
        let nets = directZone
        XCTAssertGreaterThan(nets.count, 8_000, "список подсетей России не нашёлся")

        let russian: [(String, [String])] = [
            ("МАХ", ["155.212.204.5", "155.212.204.74", "155.212.204.78",
                     "155.212.204.140", "155.212.204.143", "155.212.204.193"]),
            ("Госуслуги", ["213.59.253.7", "213.59.254.7"]),
            ("Налоговая", ["195.208.66.236"]),
            ("Мос.ру", ["212.11.155.134"]),
            ("Сбербанк", ["84.252.149.206"]),
            ("Т-Банк", ["178.130.128.27"]),
            ("Альфа-Банк", ["217.12.104.100"]),
            ("ВТБ", ["195.242.82.13", "195.242.83.13"]),
            ("ВКонтакте", ["87.240.129.133", "87.240.132.67", "93.186.225.194"]),
            ("Почта Mail.ru", ["185.180.201.1", "89.221.239.1", "90.156.232.4"]),
            ("Яндекс", ["5.255.255.77", "77.88.44.55", "77.88.55.88"]),
            ("Озон", ["185.73.193.68", "185.73.194.82"]),
            ("Wildberries", ["185.62.202.2"]),
            ("Авито", ["176.114.120.24", "176.114.124.24"]),
            ("2ГИС", ["91.236.49.6"]),
            ("РЖД", ["212.164.138.120", "212.164.138.131"]),
            ("Почта России", ["212.164.140.129", "212.164.140.153"]),
            ("Аэрофлот", ["195.209.66.33"]),
            ("Ростелеком", ["87.226.162.216"]),
        ]

        for (name, addresses) in russian {
            for address in addresses {
                XCTAssertTrue(goesDirect(address, in: nets),
                              "\(name) (\(address)) должен идти напрямую, иначе он не пустит из Казахстана")
            }
        }
    }

    func testBlockedServicesGoThroughTunnel() {
        let nets = directZone

        let blocked: [(String, [String])] = [
            ("Instagram", ["157.240.253.174"]),
            ("Facebook", ["157.240.253.35"]),
            ("X (Twitter)", ["104.244.42.129", "104.244.42.65"]),
            ("YouTube", ["142.250.74.14", "172.217.16.78"]),
            ("ChatGPT", ["104.18.32.115", "172.64.155.141"]),
            ("Claude", ["160.79.104.10"]),
            ("Google AI Studio", ["142.250.74.14"]),
            ("Discord", ["162.159.128.233", "162.159.136.232"]),
            ("LinkedIn", ["13.107.42.14"]),
            ("Spotify", ["35.186.224.25"]),
            ("GitHub", ["140.82.121.4"]),
            ("GitHub Pages", ["185.199.108.153"]),
            ("Fastly (CDN многих сервисов)", ["151.101.1.140", "146.75.2.10", "199.232.5.100"]),
        ]

        for (name, addresses) in blocked {
            for address in addresses {
                XCTAssertFalse(goesDirect(address, in: nets),
                               "\(name) (\(address)) обязан уходить в туннель, иначе сервис останется заблокированным")
            }
        }
    }

    func testWorkResourcesStayInTunnel() {
        // Единственный переключатель: включён — рабочие адреса идут через VPN.
        let nets = directZone
        for host in WorkFilter.hosts {
            XCTAssertFalse(goesDirect(host, in: nets), "\(host) должен уходить в туннель")
        }
    }
}
