import Foundation

/// Обновление службы без человека.
///
/// Приложение обновляло себя само, а службу — только после пароля
/// администратора. Пароль не вводили: окно появлялось, когда его не ждали,
/// и его закрывали. В итоге на Mac 4 октября работала служба 3.5.1, хотя
/// исправление «сон — не зависание» вышло днём раньше в 3.6.1, и служба
/// продолжала перезапускаться после каждого сна.
///
/// Служба и так работает с правами системы, пароль ей не нужен. Поэтому
/// она сама смотрит, не вышла ли новая версия, скачивает образ по
/// постоянной ссылке, проверяет его и ставит свои файлы. Скачивает она
/// в свою закрытую папку и только по нашей ссылке: подложить ей чужую
/// программу из-под обычного пользователя нельзя. Решение принято
/// осознанно, владельцем: исправление должно доходить без человека.
public enum SelfUpdate {

    public static let base =
        "https://github.com/viktorbeloglazov-design/vpn/releases/download/latest"
    public static var versionURL: URL { URL(string: "\(base)/mac-version.txt")! }
    public static var imageURL: URL { URL(string: "\(base)/QPVPN-mac.dmg")! }

    /// С какой версии служба обновляет себя сама.
    ///
    /// Службу старше этой в последний раз обновляет приложение — с паролем,
    /// как раньше: сама она этого не умеет.
    public static let since = "3.7.0"

    /// Как часто смотреть, не вышла ли новая версия.
    ///
    /// Файл с номером весит десяток байт, а исправление, которое лежит
    /// на сервере, но не стоит у человека, не помогает никому.
    public static let checkEvery: TimeInterval = 3 * 60 * 60

    /// После неудачи пробуем раньше, но не долбим сервер.
    public static let retryAfterFailure: TimeInterval = 30 * 60

    /// Первая проверка — не сразу после запуска: сначала туннель.
    public static let firstCheckAfter: TimeInterval = 120

    /// Приложение кладёт сюда файл, когда человек нажал «Обновить» или
    /// когда оно само увидело новую версию. Служба замечает его за
    /// полминуты и проверяет сразу, не дожидаясь своего часа.
    public static var requestFile: String { Paths.stateDir + "/obnovit-sejchas" }

    /// Чем кончилась последняя попытка — для отчёта диагностики.
    public static var resultFile: String { Paths.stateDir + "/obnovlenie.txt" }

    /// Куда служба складывает скачанное. Рядом со своими файлами, чтобы
    /// подмена была переименованием, а не копированием, и только для root.
    public static var workDir: String { Paths.helperDir + "/.obnovlenie" }

    /// Опознавательный знак нашего приложения в образе.
    public static let bundleIdentifier = "com.kupibas.vpn"

    /// Файлы службы внутри приложения. kupibasvpnd обязателен,
    /// остальные — утилиты туннеля, которые ставятся рядом.
    public static let helperFiles = ["kupibasvpnd", "amneziawg-go", "awg", "wireguard-go", "wg"]

    /// Пора ли проверять.
    ///
    /// - sinceStart: сколько секунд служба работает.
    /// - sinceLastCheck: сколько прошло с прошлой проверки; nil — не проверяли.
    /// - lastFailed: прошлая проверка не удалась.
    /// - requested: приложение попросило проверить сейчас.
    public static func isDue(sinceStart: TimeInterval,
                             sinceLastCheck: TimeInterval?,
                             lastFailed: Bool = false,
                             requested: Bool) -> Bool {
        if requested { return true }
        guard sinceStart >= firstCheckAfter else { return false }
        guard let sinceLastCheck else { return true }
        return sinceLastCheck >= (lastFailed ? retryAfterFailure : checkEvery)
    }

    /// Обновляет ли служба этой версии себя сама.
    public static func selfUpdates(helperVersion: String?) -> Bool {
        guard let helperVersion, Versions.isPlausible(helperVersion) else { return false }
        return !Versions.isNewer(since, than: helperVersion)
    }

    /// Что проверить в скачанном приложении, прежде чем ставить.
    ///
    /// Возвращает nil, если всё в порядке, иначе — что не так.
    public static func problem(bundleIdentifier found: String?,
                               bundleVersion: String?,
                               expectedVersion: String,
                               presentHelperFiles: Set<String>) -> String? {
        guard found == bundleIdentifier else {
            return "в образе чужое приложение (\(found ?? "без опознавательного знака"))"
        }
        guard bundleVersion == expectedVersion else {
            return "в образе версия \(bundleVersion ?? "—"), а объявлена \(expectedVersion)"
        }
        guard presentHelperFiles.contains("kupibasvpnd") else {
            return "в образе нет файла службы"
        }
        guard presentHelperFiles.contains("amneziawg-go") || presentHelperFiles.contains("wireguard-go") else {
            return "в образе нет утилиты туннеля"
        }
        return nil
    }

    /// Строка для отчёта: что случилось с обновлением последний раз.
    public static func writeResult(_ text: String, now: Date = Date()) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        try? "\(formatter.string(from: now))  \(text)\n"
            .write(toFile: resultFile, atomically: true, encoding: .utf8)
        // Файл читает приложение от имени человека.
        chmod(resultFile, 0o644)
    }

    public static func readResult() -> String? {
        guard let text = try? String(contentsOfFile: resultFile, encoding: .utf8) else { return nil }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }
}

/// Сравнение номеров версий.
public enum Versions {

    /// Свежее ли «1.2.10», чем «1.2.9».
    ///
    /// Сравниваем числами по частям: по буквам «10» оказалось бы меньше «9».
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = parts(candidate)
        let right = parts(current)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Похоже ли на номер версии то, что прислал сервер.
    ///
    /// Вместо файла может прийти страница ошибки или пустота — такое
    /// за версию принимать нельзя.
    public static func isPlausible(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 20,
              value.first?.isNumber == true, value.last?.isNumber == true else { return false }
        return value.allSatisfy { $0.isNumber || $0 == "." }
    }

    private static func parts(_ version: String) -> [Int] {
        version.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
            .compactMap { piece in Int(piece.prefix { $0.isNumber }) }
    }
}
