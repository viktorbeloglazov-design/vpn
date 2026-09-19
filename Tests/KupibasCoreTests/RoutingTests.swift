import XCTest
@testable import KupibasCore

/// Главный фильтр для Mac: те же адреса, что и на телефоне.
final class RoutingTests: XCTestCase {

    private var ruZone: [Ipv4Net] {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // KupibasCoreTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // корень
            .appendingPathComponent("Resources/ru_ipv4.txt")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        return RuZone.parse(text)
    }

    private func bypasses(_ address: String, in nets: [Ipv4Net]) -> Bool {
        guard let net = Cidr.parse(address) else { return false }
        return nets.contains { net.start >= $0.start && Int64(net.start) <= $0.endInclusive }
    }

    func testRuZoneIsBundled() {
        XCTAssertGreaterThan(ruZone.count, 8_000, "список подсетей России не нашёлся рядом с проектом")
    }

    func testRussianServicesBypassTunnel() {
        let nets = ruZone
        for (address, name) in [("5.255.255.242", "Яндекс"),
                                ("77.88.8.8", "Яндекс DNS"),
                                ("87.240.190.78", "ВКонтакте"),
                                ("194.54.14.131", "Сбер"),
                                ("2.60.0.1", "МТС")] {
            XCTAssertTrue(bypasses(address, in: nets), "\(name) должен идти напрямую")
        }
    }

    func testBlockedServicesStayInTunnel() {
        let nets = ruZone
        for (address, name) in [("157.240.229.35", "Facebook"),
                                ("142.250.185.110", "Google"),
                                ("104.244.42.1", "Twitter")] {
            XCTAssertFalse(bypasses(address, in: nets), "\(name) должен идти через VPN")
        }
    }

    func testWorkResourcesAreSubtractedFromBypass() {
        // Рабочий адрес лежит в российской зоне, но мимо туннеля уходить
        // не должен: иначе переключатель «Рабочие ресурсы» ничего не значит.
        let work = WorkFilter.hosts.compactMap { Cidr.parse($0) }
        XCTAssertFalse(work.isEmpty, "рабочие адреса не разобрались")

        let nets = ruZone
        XCTAssertTrue(work.allSatisfy { bypasses($0.text, in: nets) },
                      "предполагается, что рабочий адрес выдан России")

        let trimmed = Cidr.subtract(nets, work)
        for net in work {
            XCTAssertFalse(bypasses(net.text, in: trimmed), "\(net.text) не должен уходить мимо туннеля")
        }
    }

    func testSubtractKeepsEverythingElse() {
        let nets = [Cidr.parse("10.0.0.0/8")!]
        let holes = [Cidr.parse("10.1.2.3/32")!]
        let trimmed = Cidr.subtract(nets, holes)

        XCTAssertEqual(trimmed.reduce(Int64(0)) { $0 + $1.size }, (1 << 24) - 1)
        XCTAssertFalse(bypasses("10.1.2.3", in: trimmed))
        XCTAssertTrue(bypasses("10.1.2.4", in: trimmed))
        XCTAssertTrue(bypasses("10.255.255.255", in: trimmed))
    }

    func testSwitchesDecideMode() {
        var config = TunnelConfig()
        XCTAssertTrue(config.mainFilter)
        XCTAssertEqual(config.effectiveMode, .exclude)

        config.fullTunnel = true
        XCTAssertEqual(config.effectiveMode, .full)

        config.fullTunnel = false
        config.mainFilter = false
        config.mode = .include
        XCTAssertEqual(config.effectiveMode, .include)
    }
}
