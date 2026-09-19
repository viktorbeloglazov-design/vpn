import Foundation
import AppKit
import KupibasCore

/// Установка и удаление привилегированной службы прямо из приложения.
///
/// Скрипт установки лежит внутри бандла, а права root запрашиваются штатным
/// системным окном — пользователю не нужен терминал.
enum HelperInstaller {

    enum Action {
        case install
        case uninstall

        var argument: String? {
            switch self {
            case .install: return nil
            case .uninstall: return "--uninstall"
            }
        }
    }

    /// Путь к скрипту внутри бандла приложения.
    static var scriptPath: String? {
        let path = Bundle.main.bundlePath + "/Contents/Resources/install-helper.sh"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// Запускается ли приложение из собранного бандла со службой внутри.
    static var isBundled: Bool { scriptPath != nil }

    /// Выполняет действие. Возвращает nil при успехе или текст ошибки.
    static func run(_ action: Action) -> String? {
        guard let scriptPath else {
            return "Приложение запущено не из бандла — установите службу командой sudo ./scripts/install.sh"
        }

        var command = shellQuoted(scriptPath)
        if let argument = action.argument {
            command += " " + argument
        }

        let source = "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            return "Не удалось подготовить установку."
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        guard let errorInfo else { return nil }

        let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
        if code == -128 {
            return nil // пользователь закрыл окно ввода пароля — это не ошибка
        }
        let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "неизвестная ошибка"
        return "Установка не удалась: \(message)"
    }

    /// Оборачивает путь в одинарные кавычки для /bin/sh.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Экранирует строку для помещения внутрь двойных кавычек AppleScript.
    private static func appleScriptEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
