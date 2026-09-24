import XCTest
@testable import KupibasCore

/// Ежедневный отчёт: имя файла, заголовок и уборка старого.
final class DailyReportTests: XCTestCase {

    private func день(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: text)!
    }

    func testИмяФайлаЭтоДата() {
        XCTAssertEqual(DailyReport.name(for: день("2026-09-24")), "2026-09-24")
    }

    func testИменаСравниваютсяПоПорядкуДней() {
        // На этом построена уборка старых отчётов: даты в таком виде
        // сравниваются как строки не хуже, чем как даты.
        XCTAssertTrue(DailyReport.name(for: день("2026-08-31")) < DailyReport.name(for: день("2026-09-01")))
        XCTAssertTrue(DailyReport.name(for: день("2025-12-31")) < DailyReport.name(for: день("2026-01-01")))
    }

    func testВЗаголовкеЕстьВерсияИДата() {
        let текст = DailyReport.header(version: "3.2.0", now: день("2026-09-24"))

        XCTAssertTrue(текст.contains("3.2.0"))
        XCTAssertTrue(текст.contains("2026-09-24"))
    }

    func testОтчётЛожитсяВФайлИЧитаетсяОбратно() throws {
        // Пишем в настоящую папку «Документы» этой машины: на сборочной
        // она своя и после проверки убирается.
        let сегодня = Date()
        guard let path = DailyReport.save("проверка", now: сегодня) else {
            throw XCTSkip("Папка «Документы» недоступна на этой машине")
        }
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "проверка")
        XCTAssertTrue(path.hasSuffix(DailyReport.name(for: сегодня) + ".txt"))
    }

    func testОтчётыХранятсяМесяц() {
        XCTAssertEqual(DailyReport.keepDays, 30)
    }
}
