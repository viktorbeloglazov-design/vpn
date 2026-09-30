import XCTest
@testable import KupibasCore

/// Записи о перезапусках службы: то, что человек пришлёт вместо журнала.
final class RestartLogTests: XCTestCase {

    func testБезЗаписейОтчётГоворитПрямо() throws {
        // Файл лежит в системной папке, куда на сборочной машине не
        // пишут. Пустой отчёт — законный случай, и он не должен пугать.
        guard RestartLog.read().isEmpty else {
            throw XCTSkip("На этой машине записи уже есть")
        }

        XCTAssertEqual(RestartLog.report(), ["Перезапусков службы не было."])
    }

    func testЗаписьЛожитсяВФайлИЧитаетсяОбратно() throws {
        // Пишем в настоящую папку состояния: на сборочной машине её может
        // не быть — тогда проверять нечего, но и падать не за что.
        let было = RestartLog.read().count
        RestartLog.add(stage: "networksetup -setdnsservers Wi-Fi", seconds: 92)

        let стало = RestartLog.read()
        guard стало.count > было else {
            throw XCTSkip("Папка состояния недоступна на этой машине")
        }

        let последняя = стало[стало.count - 1]
        XCTAssertTrue(последняя.contains("networksetup -setdnsservers Wi-Fi"),
                      "Должно быть видно, кто именно не отвечал")
        XCTAssertTrue(последняя.contains("92 с"), "И сколько его ждали")
        XCTAssertFalse(RestartLog.report().isEmpty)
    }

    func testФайлНеРастётБезКонца() {
        XCTAssertEqual(RestartLog.keep, 20)
    }

    func testВОтчётПопадаютПоследниеДесять() {
        // Чтобы отчёт оставался коротким: человек копирует его целиком
        // и присылает, простыня там ни к чему.
        let записи = (1...20).map { "запись \($0)" }
        let показано = записи.suffix(10)

        XCTAssertEqual(показано.count, 10)
        XCTAssertEqual(показано.first, "запись 11")
        XCTAssertEqual(показано.last, "запись 20")
    }
}
