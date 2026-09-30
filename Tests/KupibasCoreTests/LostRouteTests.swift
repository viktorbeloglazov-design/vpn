import XCTest
@testable import KupibasCore

/// Что служба делает, когда не находит маршрут по умолчанию.
///
/// Проверки написаны по журналу с Mac за 28–30 сентября: именно там
/// служба часами писала «Маршрута по умолчанию нет вовсе» и не делала
/// ничего, потому что лечение выходило на первой же строке.
final class LostRouteTests: XCTestCase {

    private let wifi = LostRoute.Route(gateway: "192.168.0.1", interfaceName: "en0")
    private let наш = LostRoute.Route(gateway: "", interfaceName: "utun5")

    private func решение(попыток: Int,
                         маршрут: LostRoute.Route? = nil,
                         наши: Set<String> = ["utun5"],
                         прежний: LostRoute.Route? = nil,
                         сПрошлогоПерезапуска: TimeInterval = 100_000) -> LostRoute.Action {
        LostRoute.decide(attempts: попыток,
                         route: маршрут,
                         ourInterfaces: наши,
                         lastGoodRoute: прежний,
                         sinceLastRestart: сПрошлогоПерезапуска)
    }

    // MARK: - Маршрута нет вовсе: тот самый случай из журнала

    func testОтсутствиеМаршрутаБольшеНеОстаётсяБезДействия() {
        // Главное. Раньше при отсутствии маршрута лечение выходило сразу,
        // и служба висела часами: 30 сентября с 08:15 до 11:38.
        XCTAssertEqual(решение(попыток: LostRoute.restartAfter), .restartService)
    }

    func testПервыеПопыткиПростоЖдём() {
        // Переключение сети занимает секунды — дёргать службу незачем.
        XCTAssertEqual(решение(попыток: 1, прежний: wifi), .wait)
    }

    func testСоЗнакомымШлюзомСначалаПробуемВернутьМаршрутСами() {
        // Это быстрее и незаметнее перезапуска.
        XCTAssertEqual(решение(попыток: 2, прежний: wifi), .restoreVia(wifi))
        XCTAssertEqual(решение(попыток: 6, прежний: wifi), .restoreVia(wifi))
    }

    func testЕслиВернутьНеВышлоСлужбаПерезапускается() {
        XCTAssertEqual(решение(попыток: LostRoute.restartAfter, прежний: wifi), .restartService)
    }

    func testБезЗнакомогоШлюзаТолькоЖдёмДоПерезапуска() {
        XCTAssertEqual(решение(попыток: 3), .wait)
        XCTAssertEqual(решение(попыток: LostRoute.restartAfter), .restartService)
    }

    func testПустойЗапомненныйМаршрутНеИспользуется() {
        // Ни шлюза, ни интерфейса — прокладывать не через что.
        let пустой = LostRoute.Route(gateway: "", interfaceName: "")
        XCTAssertEqual(решение(попыток: 3, прежний: пустой), .wait)
    }

    // MARK: - Перезапуски не идут чередой

    func testСразуПослеПерезапускаСлужбаСебяНеТрогает() {
        // Если интернета нет по-настоящему, перезапуск не поможет,
        // и долбить им незачем.
        XCTAssertEqual(решение(попыток: 20, сПрошлогоПерезапуска: 30), .wait)
        XCTAssertEqual(решение(попыток: 20, прежний: wifi, сПрошлогоПерезапуска: 30),
                       .restoreVia(wifi))
    }

    func testЧерезДесятьМинутПерезапускСноваРазрешён() {
        XCTAssertEqual(решение(попыток: 20, сПрошлогоПерезапуска: LostRoute.restartPause),
                       .restartService)
    }

    // MARK: - Маршрут залип в туннеле

    func testЗалипшийСвойТуннельСнимаетсяОстатками() {
        XCTAssertEqual(решение(попыток: 2, маршрут: наш), .clearTunnelLeftovers)
    }

    func testЕслиОстаткиНеПомоглиСлужбаПерезапускается() {
        XCTAssertEqual(решение(попыток: LostRoute.restartAfter, маршрут: наш), .restartService)
    }

    func testЧужойТуннельОстаткамиНеЧистим() {
        // Снимать чужой VPN мы не имеем права: это не наше хозяйство.
        let чужой = LostRoute.Route(gateway: "", interfaceName: "utun9")
        XCTAssertEqual(решение(попыток: 2, маршрут: чужой), .wait)
    }

    // MARK: - Когда лечить нечего

    func testРабочийМаршрутНеТрогаем() {
        XCTAssertEqual(решение(попыток: 99, маршрут: wifi, прежний: wifi), .wait)
    }

    // MARK: - Пороги

    func testДоПерезапускаОколоДвухМинут() {
        // Попытка идёт раз в семнадцать секунд.
        XCTAssertEqual(LostRoute.restartAfter, 7)
        XCTAssertEqual(LostRoute.restartPause, 600)
    }
}
