import XCTest
@testable import KupibasCore

/// Какой маршрут по умолчанию годится, а какой — ловушка.
///
/// Это место ломало связь надолго: при переподключении служба успевала
/// прочитать собственный туннельный интерфейс и проложить через него весь
/// обход. Связь пропадала до перезапуска службы — ровно то, на что
/// жаловались: «отваливается, помогает только переустановка».
final class RouteGuardTests: XCTestCase {

    func testСвойТуннельНеГодитсяКакДорогаВОбход() {
        for name in ["utun0", "utun5", "utun12"] {
            XCTAssertTrue(RouteGuard.isTunnel(interface: name), name)
            XCTAssertFalse(RouteGuard.isUsable(gateway: "10.8.0.1", interface: name),
                           "через \(name) обход прокладывать нельзя — это и есть туннель")
        }
    }

    func testЧужиеТуннелиТожеНеГодятся() {
        for name in ["ipsec0", "ppp0", "gif0", "stf0"] {
            XCTAssertTrue(RouteGuard.isTunnel(interface: name), name)
        }
    }

    func testОбычныеИнтерфейсыГодятся() {
        for name in ["en0", "en1", "bridge0", "ap1"] {
            XCTAssertFalse(RouteGuard.isTunnel(interface: name), name)
            XCTAssertTrue(RouteGuard.isUsable(gateway: "192.168.1.1", interface: name), name)
        }
    }

    func testБезШлюзаНоСИнтерфейсомГодится() {
        // На мобильном интернете шлюза может не быть вовсе.
        XCTAssertTrue(RouteGuard.isUsable(gateway: "", interface: "en0"))
    }

    func testПустойМаршрутНеГодится() {
        XCTAssertFalse(RouteGuard.isUsable(gateway: "", interface: ""))
    }

    func testРегистрИПробелыНеМешают() {
        XCTAssertTrue(RouteGuard.isTunnel(interface: " UTUN4 "))
        XCTAssertFalse(RouteGuard.isUsable(gateway: "10.8.0.1", interface: " UTUN4 "))
    }
}
