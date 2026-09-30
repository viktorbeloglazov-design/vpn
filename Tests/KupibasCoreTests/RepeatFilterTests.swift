import XCTest
@testable import KupibasCore

/// Подавление повторов в журнале.
final class RepeatFilterTests: XCTestCase {

    func testПерваяЗаписьПроходитСразу() {
        var фильтр = RepeatFilter(pause: 600)

        XCTAssertEqual(фильтр.passing("нет маршрута", now: 0), "нет маршрута")
    }

    func testПовторПодрядПридерживается() {
        // Именно так журнал и забивался: одна строка каждые 17 секунд.
        var фильтр = RepeatFilter(pause: 600)
        _ = фильтр.passing("нет маршрута", now: 0)

        XCTAssertNil(фильтр.passing("нет маршрута", now: 17))
        XCTAssertNil(фильтр.passing("нет маршрута", now: 34))
        XCTAssertNil(фильтр.passing("нет маршрута", now: 599))
    }

    func testЧерезПаузуПовторПроходитИГоворитСколькоМолчал() {
        var фильтр = RepeatFilter(pause: 600)
        _ = фильтр.passing("нет маршрута", now: 0)
        for секунда in stride(from: 17.0, through: 595.0, by: 17.0) {
            _ = фильтр.passing("нет маршрута", now: секунда)
        }

        let текст = фильтр.passing("нет маршрута", now: 600)

        XCTAssertNotNil(текст)
        XCTAssertTrue(текст!.hasPrefix("нет маршрута"))
        XCTAssertTrue(текст!.contains("повторилось ещё 35 раз"),
                      "Счёт пропущенных не должен теряться: \(текст!)")
    }

    func testДругаяЗаписьПроходитСразуИЗакрываетСчёт() {
        var фильтр = RepeatFilter(pause: 600)
        _ = фильтр.passing("нет маршрута", now: 0)
        _ = фильтр.passing("нет маршрута", now: 17)
        _ = фильтр.passing("нет маршрута", now: 34)

        let текст = фильтр.passing("туннель поднят", now: 40)

        XCTAssertNotNil(текст)
        XCTAssertTrue(текст!.contains("повторилась ещё 2 раз"),
                      "Сколько раз молчали — должно быть сказано: \(текст!)")
        XCTAssertTrue(текст!.hasSuffix("туннель поднят"))
    }

    func testЧередованиеДвухЗаписейНеПридерживается() {
        // «Маршрута нет» и «нет подключения» шли парами — обе нужны.
        var фильтр = RepeatFilter(pause: 600)

        XCTAssertNotNil(фильтр.passing("первая", now: 0))
        XCTAssertNotNil(фильтр.passing("вторая", now: 1))
        XCTAssertNotNil(фильтр.passing("первая", now: 2))
    }

    func testПослеПаузыСчётНачинаетсяЗаново() {
        var фильтр = RepeatFilter(pause: 600)
        _ = фильтр.passing("нет маршрута", now: 0)
        _ = фильтр.passing("нет маршрута", now: 17)
        _ = фильтр.passing("нет маршрута", now: 600)

        let текст = фильтр.passing("нет маршрута", now: 1200)

        XCTAssertNotNil(текст)
        XCTAssertFalse(текст!.contains("ещё"), "Счёт должен был обнулиться: \(текст!)")
    }
}
