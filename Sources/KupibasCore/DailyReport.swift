import Foundation

/// Ежедневный отчёт о работе программы — файлом в папке «Документы».
///
/// Нужен затем, чтобы разбираться по записям, а не по памяти. Когда
/// человек говорит «вчера днём отвалилось», в отчёте видно, что было:
/// подключались или нет, сколько прошло данных, какой размер пакета
/// подобрался, что ответил сервер.
///
/// Файл на каждый день, переписывается по ходу дня, так что к вечеру
/// в нём последнее состояние. Старше месяца — удаляются сами.
///
/// Ключей и паролей в отчёте нет: только адрес сервера, счётчики и
/// состояние. Такой файл можно пересылать не задумываясь.
public enum DailyReport {

    /// Сколько дней держим отчёты.
    public static let keepDays = 30

    public static var directory: String {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Documents"
        return documents + "/QP VPN/отчёты"
    }

    public static func path(for day: Date) -> String {
        directory + "/" + name(for: day) + ".txt"
    }

    /// Складывает отчёт за сегодня. Возвращает путь или nil.
    @discardableResult
    public static func save(_ text: String, now: Date = Date()) -> String? {
        do {
            try FileManager.default.createDirectory(atPath: directory,
                                                    withIntermediateDirectories: true)
            let target = path(for: now)
            try text.write(toFile: target, atomically: true, encoding: .utf8)
            forget(now: now)
            return target
        } catch {
            // Папка недоступна — отчёт не главное, работе это не мешает.
            return nil
        }
    }

    /// Убирает отчёты старше месяца, чтобы папка не росла без конца.
    public static func forget(now: Date = Date()) {
        guard let edge = Calendar.current.date(byAdding: .day, value: -keepDays, to: now),
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory)
        else { return }

        let edgeName = name(for: edge)
        for file in files where file.hasSuffix(".txt") {
            let day = String(file.dropLast(4))
            // Имена вида 2026-09-24 сравниваются как строки не хуже, чем даты.
            if day.count == edgeName.count && day < edgeName {
                try? FileManager.default.removeItem(atPath: directory + "/" + file)
            }
        }
    }

    /// Имя файла за этот день: 2026-09-24.
    public static func name(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }

    /// Заголовок отчёта: что это за файл и когда записан.
    public static func header(version: String, now: Date = Date()) -> String {
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH:mm"
        return """
            QP VPN для Mac \(version)
            Отчёт за \(name(for: now)), записан в \(time.string(from: now))

            """
    }
}
