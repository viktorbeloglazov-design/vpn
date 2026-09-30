import Foundation

/// Записи о том, когда и почему служба перезапускала себя сама.
///
/// Жалоба «служба отваливается» без подробностей неотличима от десятка
/// разных поломок. Полный журнал службы лежит в системной папке, куда
/// человек не полезет, — и правильно, ему там не место.
///
/// Поэтому короткие записи о перезапусках ложатся рядом с настройками,
/// а приложение показывает их в отчёте диагностики. Человек нажимает
/// «Скопировать отчёт» и присылает; в отчёте видно, что именно не
/// отвечало и как часто. Ключей и адресов в этих строках нет.
public enum RestartLog {

    public static var path: String { Paths.stateDir + "/perezapuski.txt" }

    /// Сколько записей держим: больше и не нужно, а файл не растёт.
    public static let keep = 20

    /// Записывает причину перезапуска. Вызывается службой перед выходом.
    public static func add(stage: String, seconds: Int, now: Date = Date()) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(formatter.string(from: now))  встала на «\(stage)» на \(seconds) с"

        var lines = read()
        lines.append(line)
        if lines.count > keep { lines.removeFirst(lines.count - keep) }

        try? FileManager.default.createDirectory(atPath: Paths.stateDir,
                                                 withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n")
            .write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Записи, от старых к новым.
    public static func read() -> [String] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    /// Строки для отчёта диагностики.
    public static func report(now: Date = Date()) -> [String] {
        let lines = read()
        guard !lines.isEmpty else { return ["Перезапусков службы не было."] }

        var out = ["Служба перезапускала себя сама (последние \(lines.count)):"]
        out.append(contentsOf: lines.suffix(10).map { "  " + $0 })
        return out
    }
}
