import Foundation
import AppKit

/// Журнал запуска приложения.
///
/// Если приложение падает до появления окна, в Dock видно только прыгающий
/// значок и больше ничего. Поэтому каждый шаг запуска отмечается в файле —
/// по нему видно, на чём всё оборвалось.
enum Diagnostics {

    static let logPath: String = {
        let directory = NSHomeDirectory() + "/Library/Logs"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return directory + "/QPVPN.log"
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Ставит перехватчик необработанных исключений и отмечает старт.
    static func bootstrap() {
        NSSetUncaughtExceptionHandler { exception in
            Diagnostics.log("ИСКЛЮЧЕНИЕ \(exception.name.rawValue): \(exception.reason ?? "")")
            Diagnostics.log("стек: \(exception.callStackSymbols.prefix(12).joined(separator: " | "))")
        }

        let bundlePath = Bundle.main.bundlePath
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        log("--- запуск, версия \(version), бандл \(bundlePath) ---")
    }

    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))

        let url = URL(fileURLWithPath: logPath)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(Data(line.utf8))
        } else {
            try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
}
