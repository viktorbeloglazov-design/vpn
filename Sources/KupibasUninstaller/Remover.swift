import Foundation
import AppKit

/// Запуск уборки с правами администратора.
///
/// Служба, журналы и системные каталоги принадлежат root, поэтому без
/// повышения прав их не убрать. Пароль спрашивает штатное окно macOS —
/// то же самое, что при установке службы.
enum Remover {

    enum Outcome {
        case done(String)
        /// Человек закрыл окно ввода пароля.
        case cancelled
        case failed(String)
    }

    /// Скрипт уборки лежит внутри бандла — рядом с самой программой.
    static var scriptPath: String? {
        let path = Bundle.main.bundlePath + "/Contents/Resources/uninstall-mac.sh"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static func run(apps: [String], keepSettings: Bool) -> Outcome {
        guard let scriptPath else {
            return .failed("Внутри программы нет файла уборки — скачайте её заново.")
        }

        var parts = [quoted(scriptPath)]
        if keepSettings { parts.append("--keep-settings") }
        parts.append(contentsOf: apps.map(quoted))

        let source = """
            do shell script "\(escaped(parts.joined(separator: " ")))" \
            with administrator privileges
            """
        guard let script = NSAppleScript(source: source) else {
            return .failed("Не удалось подготовить уборку.")
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -128 { return .cancelled }
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "неизвестная ошибка"
            return .failed("Убрать не вышло: \(message)")
        }

        return .done(result.stringValue ?? "Готово.")
    }

    /// Путь в кавычках для оболочки: пробелы в путях — обычное дело.
    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Та же строка, но уже внутри команды AppleScript.
    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
