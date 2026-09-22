import Foundation

/// Поиск всего, что QP VPN оставляет на компьютере.
///
/// Приложение ставится перетаскиванием и обновляется тем же способом,
/// поэтому копий легко накапливается несколько: одна в «Программах»,
/// другая в «Загрузках», третья на рабочем столе. Работает при этом та,
/// которую открыли последней, а человек видит разнобой версий и не может
/// понять, какая из них настоящая.
///
/// Здесь собрано всё, что можно найти и убрать.
public enum Leftovers {

    /// Что именно нашли.
    public enum Kind: String, Sendable {
        case app = "Приложение"
        case helper = "Служба"
        case settings = "Настройки"
        case log = "Журналы"
        case leftover = "Остатки"

        /// Можно ли это удалить только с правами администратора.
        public var needsAdmin: Bool {
            switch self {
            case .app, .settings: return false
            case .helper, .log, .leftover: return true
            }
        }
    }

    public struct Item: Identifiable, Sendable {
        public var id: String { path }
        public let path: String
        public let kind: Kind
        /// Размер в байтах; 0 — посчитать не вышло.
        public let size: Int64
        /// Версия, если это приложение и её удалось прочитать.
        public let version: String?
        /// Эта копия сейчас и работает — её удалять нельзя.
        public let isCurrent: Bool

        public var name: String { (path as NSString).lastPathComponent }
    }

    /// Наш опознавательный знак. По нему копию видно, как бы её ни назвали.
    public static let bundleIdentifier = "com.kupibas.vpn"

    // MARK: - Поиск

    /// Ищет все следы. `currentApp` — путь к работающей копии, её не трогаем.
    public static func find(currentApp: String? = nil,
                            home: String = NSHomeDirectory(),
                            fileManager: FileManager = .default) -> [Item] {
        var items: [Item] = []
        var seen = Set<String>()

        func add(_ path: String, _ kind: Kind, version: String? = nil) {
            let clean = (path as NSString).standardizingPath
            guard !seen.contains(clean), fileManager.fileExists(atPath: clean) else { return }
            seen.insert(clean)
            items.append(Item(path: clean,
                              kind: kind,
                              size: size(of: clean, fileManager: fileManager),
                              version: version,
                              isCurrent: clean == (currentApp as NSString?)?.standardizingPath))
        }

        for app in applications(home: home, fileManager: fileManager) {
            add(app, .app, version: version(of: app))
        }

        // Служба: без её удаления новая установка может подхватить старую.
        add(Paths.daemonPlist, .helper)
        add(Paths.helperDir, .helper)
        add(Paths.runtimeDir, .helper)
        add("/var/run/amneziawg", .helper)

        add(Paths.stateDir, .settings)
        add("/Library/Application Support/QPVPN", .settings)
        add("\(home)/Library/Preferences/\(bundleIdentifier).plist", .settings)
        add("\(home)/Library/Caches/\(bundleIdentifier)", .settings)
        add("\(home)/Library/Saved Application State/\(bundleIdentifier).savedState", .settings)

        add(Paths.logFile, .log)
        add("/var/log/kupibas-vpn-install.log", .log)

        // Хвост от неудачной замены приложения при обновлении.
        add("/Applications/QPVPN.app.update", .leftover)
        add("\(home)/Applications/QPVPN.app.update", .leftover)

        return items
    }

    /// Работают ли прямо сейчас копии приложения, и какие.
    ///
    /// Приложение живёт в строке меню и после закрытия окна остаётся
    /// в памяти. Если старая копия не завершена, двойной щелчок по новой
    /// ничего не откроет: система увидит, что программа с таким же
    /// опознавательным знаком уже работает, и просто покажет старую.
    /// Человек ставит новую версию, а видит прежнюю.
    public static func running() -> [String] {
        let output = run("/bin/ps", ["-Ao", "comm="]) ?? ""
        return output
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("/QPVPN.app/Contents/MacOS/") || $0.hasSuffix("/QPVPN") }
            .map { path in
                // Из пути к исполняемому файлу достаём сам бандл.
                if let range = path.range(of: ".app/Contents/MacOS/") {
                    return String(path[path.startIndex..<range.lowerBound]) + ".app"
                }
                return path
            }
            .reduce(into: [String]()) { result, path in
                if !result.contains(path) { result.append(path) }
            }
    }

    /// Все копии приложения, где бы они ни лежали.
    ///
    /// Сначала спрашиваем Spotlight: он знает про копии в папках, куда мы
    /// сами не заглянем. Если он выключен или молчит, обходим привычные
    /// места руками — этого хватает почти всегда.
    public static func applications(home: String = NSHomeDirectory(),
                                    fileManager: FileManager = .default) -> [String] {
        var found = Set(spotlightApplications())

        let directories = [
            "/Applications",
            "\(home)/Applications",
            "\(home)/Desktop",
            "\(home)/Downloads",
            "/Applications/Utilities",
            // Перетащить в Корзину — не значит удалить: копия лежит там
            // целиком, и система продолжает её видеть.
            "\(home)/.Trash",
        ]
        for directory in directories {
            let contents = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
            for entry in contents where entry.hasSuffix(".app") {
                let path = directory + "/" + entry
                if identifier(of: path) == bundleIdentifier { found.insert(path) }
            }
        }
        return found.sorted()
    }

    private static func spotlightApplications() -> [String] {
        let output = run("/usr/bin/mdfind",
                         ["kMDItemCFBundleIdentifier == '\(bundleIdentifier)'"])
        return (output ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasSuffix(".app") }
    }

    // MARK: - Чтение бандла

    public static func identifier(of app: String) -> String? {
        plistValue(app, "CFBundleIdentifier")
    }

    public static func version(of app: String) -> String? {
        plistValue(app, "CFBundleShortVersionString")
    }

    private static func plistValue(_ app: String, _ key: String) -> String? {
        let path = app + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return plist[key] as? String
    }

    // MARK: - Размер

    static func size(of path: String, fileManager: FileManager = .default) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }

        if !isDirectory.boolValue {
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }

        var total: Int64 = 0
        guard let walker = fileManager.enumerator(atPath: path) else { return 0 }
        for case let entry as String in walker {
            let attributes = try? fileManager.attributesOfItem(atPath: path + "/" + entry)
            total += (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
        return total
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
        return String(data: data, encoding: .utf8)
    }
}
