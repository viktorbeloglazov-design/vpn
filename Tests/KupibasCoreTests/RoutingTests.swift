import XCTest
@testable import KupibasCore

/// Арифметика подсетей и выбор режима.
final class RoutingTests: XCTestCase {

    private func bypasses(_ address: String, in nets: [Ipv4Net]) -> Bool {
        guard let net = Cidr.parse(address) else { return false }
        return nets.contains { net.start >= $0.start && Int64(net.start) <= $0.endInclusive }
    }

    func testРабочиеАдресаИдутЧерезVPN() {
        // Единственный переключатель, который человек выбирает сам.
        let work = WorkFilter.hosts.compactMap { Cidr.parse($0) }
        XCTAssertFalse(work.isEmpty, "рабочие адреса не разобрались")
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

    func testРежимПоУмолчаниюТолькоСписок() {
        var config = TunnelConfig()
        XCTAssertFalse(config.mainFilter)
        XCTAssertEqual(config.effectiveMode, .include,
                       "через VPN идёт только список сервисов")

        config.fullTunnel = true
        XCTAssertEqual(config.effectiveMode, .full, "запас на случай, если понадобится всё через VPN")
    }
}
