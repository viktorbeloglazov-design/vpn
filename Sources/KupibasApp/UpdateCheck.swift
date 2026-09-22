import Foundation
import AppKit
import KupibasCore

/// Проверка и установка обновления.
///
/// Приложение ставится образом с сайта, мимо магазина, поэтому напомнить о
/// новой версии некому — делаем это сами. Рядом со сборкой лежит файл с
/// номером версии строкой: его и читаем, он весит десяток байт.
///
/// Ссылки постоянные: имя файла без номера, выпуск с меткой latest. Они не
/// меняются от версии к версии, настраивать нечего.
enum UpdateCheck {

    private static let base =
        "https://github.com/viktorbeloglazov-design/vpn/releases/download/latest"

    private static var versionURL: URL { URL(string: "\(base)/mac-version.txt")! }
    private static var imageURL: URL { URL(string: "\(base)/QPVPN-mac.dmg")! }

    /// Раз в сутки — чаще незачем, реже можно пропустить важное.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Свежая версия на сервере, либо nil — узнать не вышло.
    static func latestVersion() -> String? {
        var request = URLRequest(url: versionURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        var result: String?
        let done = DispatchSemaphore(value: 0)
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, _ in
            defer { done.signal() }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data, let text = String(data: data, encoding: .utf8) else { return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = value.first, first.isNumber { result = value }
        }.resume()
        _ = done.wait(timeout: .now() + 20)
        return result
    }

    /// Скачивает образ во временный каталог.
    static func download() -> URL? {
        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 120

        var result: URL?
        let done = DispatchSemaphore(value: 0)
        URLSession(configuration: .ephemeral).downloadTask(with: request) { location, response, _ in
            defer { done.signal() }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let location else { return }
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent("QPVPN-update.dmg")
            try? FileManager.default.removeItem(at: target)
            guard (try? FileManager.default.moveItem(at: location, to: target)) != nil else { return }
            result = target
        }.resume()
        _ = done.wait(timeout: .now() + 180)
        return result
    }

    /// Что вышло из установки обновления.
    enum Outcome {
        /// Приложение заменено; осталось перезапустить.
        case replaced
        /// Заменить не вышло — образ показан в Finder, дальше руками.
        case openedInFinder(String)
    }

    /// Ставит скачанный образ поверх работающего приложения.
    ///
    /// Человек ждёт, что «Обновить» обновит, а не откроет ему окно Finder
    /// с предложением что-то перетащить. Поэтому делаем всё сами:
    /// подключаем образ, забираем из него приложение, кладём на место
    /// текущего и просим перезапуститься.
    ///
    /// macOS разрешает подменить работающее приложение: запущенный процесс
    /// продолжает жить со старым содержимым в памяти. Замена атомарная —
    /// либо новое приложение целиком, либо остаётся старое.
    static func install(_ image: URL) -> Outcome {
        guard let mount = attach(image) else {
            NSWorkspace.shared.open(image)
            return .openedInFinder("Не удалось открыть образ — он открыт в Finder.")
        }
        defer { detach(mount) }

        let source = mount.appendingPathComponent("QPVPN.app")
        guard FileManager.default.fileExists(atPath: source.path),
              bundleIdentifier(of: source) == Bundle.main.bundleIdentifier else {
            NSWorkspace.shared.open(image)
            return .openedInFinder("В образе не нашлось нашего приложения — он открыт в Finder.")
        }

        let target = Bundle.main.bundleURL
        do {
            try replace(target, with: source)
            return .replaced
        } catch {
            NSWorkspace.shared.open(image)
            return .openedInFinder("Заменить приложение не вышло (\(error.localizedDescription)). "
                + "Образ открыт в Finder — перетащите QP VPN в «Программы» с заменой.")
        }
    }

    /// Кладёт новое приложение на место старого одним движением.
    private static func replace(_ target: URL, with source: URL) throws {
        let fm = FileManager.default
        // Рядом с заменяемым, а не во временной папке: replaceItemAt работает
        // только в пределах одного тома.
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent("QPVPN.app.update")
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: source, to: staging)

        // Файл, скачанный нами, карантина не получает — его ставят браузеры.
        // Но если он там всё же оказался, macOS откажется открывать копию
        // молча, и человек решит, что обновление сломало программу.
        clearQuarantine(staging)

        do {
            _ = try fm.replaceItemAt(target, withItemAt: staging)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Перезапускает приложение: ждёт выхода текущего и открывает новое.
    ///
    /// Дочерний процесс переживает родителя, поэтому открыть новое приложение
    /// после собственного выхода можно только так.
    static func relaunchAfterQuit() {
        let path = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            sleep 0.4
            /usr/bin/open -n "\(path)"
            """]
        try? task.run()
    }

    // MARK: - Образ

    /// Подключает образ и возвращает точку монтирования.
    private static func attach(_ image: URL) -> URL? {
        let output = run("/usr/bin/hdiutil",
                         ["attach", image.path, "-nobrowse", "-readonly", "-plist"])
        guard let data = output?.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else { return nil }

        // Точка монтирования есть только у той записи, что несёт файловую
        // систему: остальные — это разделы образа.
        for entity in entities {
            if let point = entity["mount-point"] as? String, !point.isEmpty {
                return URL(fileURLWithPath: point)
            }
        }
        return nil
    }

    private static func detach(_ mount: URL) {
        _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
    }

    private static func bundleIdentifier(of app: URL) -> String? {
        Bundle(url: app)?.bundleIdentifier
    }

    private static func clearQuarantine(_ app: URL) {
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Свежее ли «1.2.10», чем «1.2.9».
    ///
    /// Сравниваем числами по частям: по буквам «10» оказалось бы меньше «9».
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = parts(candidate)
        let right = parts(current)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        version.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
            .compactMap { piece in Int(piece.prefix { $0.isNumber }) }
    }
}
