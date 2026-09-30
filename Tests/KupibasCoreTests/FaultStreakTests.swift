import XCTest
@testable import KupibasCore

/// Осечки подряд: одна ничего не значит, три — поломка.
final class FaultStreakTests: XCTestCase {

    func testОднаОсечкаНеПоводПересоздаватьТуннель() {
        // Из-за этого связь и пропадала на минуту: один непрошедший
        // запрос — и туннель пересобирался целиком.
        var счёт = FaultStreak(limit: 3)

        XCTAssertFalse(счёт.miss())
    }

    func testТретьяОсечкаПодрядЭтоУжеПоломка() {
        var счёт = FaultStreak(limit: 3)

        XCTAssertFalse(счёт.miss())
        XCTAssertFalse(счёт.miss())
        XCTAssertTrue(счёт.miss())
    }

    func testУдачнаяПопыткаОбнуляетСчёт() {
        var счёт = FaultStreak(limit: 3)

        счёт.miss()
        счёт.miss()
        счёт.hit()

        XCTAssertEqual(счёт.current, 0)
        XCTAssertFalse(счёт.miss(), "После удачной попытки счёт начинается заново")
        XCTAssertFalse(счёт.miss())
        XCTAssertTrue(счёт.miss())
    }

    func testПослеПочинкиСчётНачинаетсяЗаново() {
        // Иначе вторая поломка чинилась бы с первой же осечки.
        var счёт = FaultStreak(limit: 3)

        счёт.miss(); счёт.miss()
        XCTAssertTrue(счёт.miss())

        XCTAssertFalse(счёт.miss(), "Сразу после починки терпим столько же, сколько вначале")
        XCTAssertFalse(счёт.miss())
        XCTAssertTrue(счёт.miss())
    }

    func testПорогМеньшеЕдиницыНевозможен() {
        // Иначе счётчик молчал бы всегда и поломку никто не заметил.
        var счёт = FaultStreak(limit: 0)

        XCTAssertEqual(счёт.limit, 1)
        XCTAssertTrue(счёт.miss())
    }
}
