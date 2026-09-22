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
        /// Убрать перечисленные копии программы, оставив ключ и настройки.
        case removeCopies([String])

        /// Какой скрипт внутри бандла исполняет это действие.
        var script: String {
            switch self {
            case .install, .uninstall: return "install-helper.sh"
            case .removeCopies: return "uninstall-mac.sh"
            }
        }

        var arguments: [String] {
            switch self {
            case .install: return []
            case .uninstall: return ["--uninstall"]
            case .removeCopies(let paths): return ["--keep-settings"] + paths
            }
        }
    }

    /// Путь к скрипту внутри бандла приложения.
    static func scriptPath(for action: Action = .install) -> String? {
        let path = Bundle.main.bundlePath + "/Contents/Resources/" + action.script
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static var scriptPath: String? { scriptPath(for: .install) }

    /// Запускается ли приложение из собранного бандла со службой внутри.
    static var isBundled: Bool { scriptPath != nil }

    /// Выполняет действие. Возвращает nil при успехе или текст ошибки.
    static func run(_ action: Action) -> String? {
        guard let path = scriptPath(for: action) else {
            return "Внутри приложения нет нужного файла. Скачайте свежую сборку "
                + "и запустите её из папки «Программы»."
        }

        var command = shellQuoted(path)
        for argument in action.arguments {
            command += " " + shellQuoted(argument)
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
