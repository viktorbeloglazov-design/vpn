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

    /// Открывает скачанный образ: дальше человек перетаскивает приложение.
    ///
    /// Подменять работающее приложение на ходу мы не беремся: это делается
    /// через отдельный процесс-помощник, и любая осечка оставляет человека
    /// без программы. Образ в Finder — способ скучный, зато надёжный.
    static func open(_ image: URL) {
        NSWorkspace.shared.open(image)
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
