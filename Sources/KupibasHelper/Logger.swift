import Foundation
import KupibasCore

final class Logger {
    private let path: String
    private let queue = DispatchQueue(label: "kupibas-vpn.logger")
    private let maxSize = 2 * 1024 * 1024
    private let formatter: DateFormatter

    /// Одна и та же запись не должна забивать журнал.
    ///
    /// В журнале с Mac строка «Маршрута по умолчанию нет вовсе»
    /// повторялась каждые семнадцать секунд часами. Журнал переполнялся
    /// и обрезался, унося начало истории — как раз то место, где видно,
    /// с чего всё началось.
    private var repeats = RepeatFilter()

    init(path: String) {
        self.path = path
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.formatter = formatter
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path,
                                           contents: nil,
                                           attributes: [.posixPermissions: NSNumber(value: Int16(0o644))])
        }
    }

    func info(_ message: String) { write("INFO", message) }
    func error(_ message: String) { write("ERROR", message) }

    /// Запись перед самым завершением службы.
    ///
    /// Обычная запись уходит в очередь и ложится на диск когда-нибудь
    /// потом. Перед выходом «потом» не наступит: процесса уже не будет,
    /// и в журнале не останется ни строчки о том, почему он ушёл.
    /// Поэтому здесь пишем сразу и ждём, пока запишется.
    func critical(_ message: String) {
        let line = "\(formatter.string(from: Date())) [ERROR] \(message)\n"
        queue.sync {
            FileHandle.standardError.write(Data(line.utf8))
            guard let handle = FileHandle(forWritingAtPath: path) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(Data(line.utf8))
            try? handle.synchronize()
        }
    }

    private func write(_ level: String, _ message: String) {
        queue.async { [path, maxSize] in
            guard let text = self.repeats.passing("[\(level)] \(message)",
                                                  now: Date().timeIntervalSince1970)
            else { return }

            let line = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "\(self.formatter.string(from: Date())) \($0)" }
                .joined(separator: "\n") + "\n"

            FileHandle.standardError.write(Data(line.utf8))
            // Открываем на чтение и запись: чтобы обрезать журнал по-умному,
            // старое содержимое надо сначала прочитать.
            guard let handle = FileHandle(forUpdatingAtPath: path) else { return }
            defer { try? handle.close() }
            Self.trimIfNeeded(path: path, handle: handle, maxSize: maxSize)
            _ = try? handle.seekToEnd()
            handle.write(Data(line.utf8))
        }
    }

    /// Освобождает место, оставляя свежую половину журнала.
    ///
    /// Раньше журнал обрезался в ноль. Разбираться после этого было
    /// не по чему: в файле оставались последние минуты, а начало
    /// поломки — самое нужное — пропадало.
    private static func trimIfNeeded(path: String, handle: FileHandle, maxSize: Int) {
        guard let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int,
              size > maxSize else { return }

        let keep = maxSize / 2
        guard (try? handle.seek(toOffset: UInt64(size - keep))) != nil,
              let data = try? handle.readToEnd()
        else {
            try? handle.truncate(atOffset: 0)
            return
        }

        // Обрезаем по началу строки, чтобы журнал не начинался с обрывка.
        let from = data.firstIndex(of: UInt8(ascii: "\n")).map { data.index(after: $0) } ?? data.startIndex
        try? handle.truncate(atOffset: 0)
        try? handle.seek(toOffset: 0)
        handle.write(Data(data[from...]))
    }
}
