import XCTest
@testable import KupibasCore

/// Когда туннель поднимать заново, а когда не трогать.
///
/// Прежняя проверка смотрела на возраст handshake и потому пересоздавала
/// туннель каждые три минуты простоя — связь дёргалась на ровном месте.
final class LinkWatchTests: XCTestCase {

    func testIdleMachineIsNeverTouched() {
        // Ноутбук стоит без дела: ни отправки, ни приёма. Час подряд.
        let watch = LinkWatch()
        var now: TimeInterval = 0
        watch.start(rx: 1_000, tx: 1_000, now: now)

        for _ in 0..<1_800 {
            now += 2
            XCTAssertFalse(watch.stalled(rx: 1_000, tx: 1_000, now: now),
                           "простой не повод рвать связь (прошло \(Int(now / 60)) мин)")
        }
    }

    func testWorkingTunnelIsNeverTouched() {
        let watch = LinkWatch()
        var now: TimeInterval = 0
        var rx = 0
        var tx = 0
        watch.start(rx: rx, tx: tx, now: now)

        for _ in 0..<1_800 {
            now += 2
            rx += 40_000
            tx += 8_000
            XCTAssertFalse(watch.stalled(rx: rx, tx: tx, now: now), "рабочий туннель трогать нельзя")
        }
    }

    func testSilenceWhileSendingIsCaught() {
        // Переезд в другую сеть: шлём, в ответ тишина.
        let watch = LinkWatch()
        var now: TimeInterval = 0
        var tx = 0
        watch.start(rx: 5_000, tx: tx, now: now)

        var caughtAt: TimeInterval?
        for _ in 0..<40 {
            now += 2
            tx += 1_500
            if watch.stalled(rx: 5_000, tx: tx, now: now), caughtAt == nil { caughtAt = now }
        }

        XCTAssertEqual(caughtAt, 46, "оборванную связь надо чинить, и не позже минуты")
    }

    func testSilenceIsGivenTimeBeforeReconnecting() {
        // Полминуты без ответа — ещё не повод: так бывает на слабом сигнале.
        let watch = LinkWatch()
        var now: TimeInterval = 0
        var tx = 0
        watch.start(rx: 5_000, tx: tx, now: now)

        for _ in 0..<15 {
            now += 2
            tx += 1_500
            XCTAssertFalse(watch.stalled(rx: 5_000, tx: tx, now: now),
                           "30 секунд тишины — рано (\(Int(now)) с)")
        }
    }

    func testRepairsAreNotRepeatedInARow() {
        // Сервер лежит: чинить каждые две секунды бессмысленно.
        let watch = LinkWatch()
        var now: TimeInterval = 0
        var tx = 0
        watch.start(rx: 5_000, tx: tx, now: now)

        var repairs = 0
        for _ in 0..<300 {
            now += 2
            tx += 1_500
            if watch.stalled(rx: 5_000, tx: tx, now: now) { repairs += 1 }
        }

        // Десять минут: одна починка примерно в две минуты.
        XCTAssertTrue((1...6).contains(repairs), "починок должно быть немного, а их \(repairs)")
    }

    func testAnswerResetsTheCountdown() {
        // Ответ пришёл — отсчёт тишины начинается заново.
        let watch = LinkWatch()
        var now: TimeInterval = 0
        var rx = 5_000
        var tx = 0
        watch.start(rx: rx, tx: tx, now: now)

        for _ in 0..<100 {
            now += 2
            tx += 1_500
            // Ответ раз в 40 секунд: редко, но связь жива.
            if Int(now) % 40 == 0 { rx += 500 }
            XCTAssertFalse(watch.stalled(rx: rx, tx: tx, now: now), "связь отвечает — трогать нечего")
        }
    }
}
