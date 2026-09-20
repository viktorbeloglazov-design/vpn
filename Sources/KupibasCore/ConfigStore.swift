import Foundation

public enum ConfigStoreError: LocalizedError {
    case directoryMissing
    case notWritable(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .directoryMissing:
            return "Каталог \(Paths.stateDir) не найден — служба kupibasvpnd ещё не установлена."
        case .notWritable(let path):
            return "Нет прав на запись в \(path). Выполните: sudo scripts/install.sh"
        case .io(let message):
            return message
        }
    }
}

/// Чтение и запись общих файлов состояния.
/// GUI пишет config.json, демон — status.json; обмен идёт только через файлы.
public enum ConfigStore {

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Paths.stateDir)
            && FileManager.default.fileExists(atPath: Paths.daemonPlist)
    }

    /// Маршрутизация зашита: что бы ни лежало в файле от прошлых версий,
    /// в работу уходит одно и то же поведение. Иначе включённый когда-то
    /// переключатель остался бы навсегда — выключить его больше негде.
    public static func loadConfig() -> TunnelConfig {
        guard let data = FileManager.default.contents(atPath: Paths.configFile),
              let config = try? JSONDecoder().decode(TunnelConfig.self, from: data) else {
            return TunnelConfig().pinned()
        }
        return config.pinned()
    }

    public static func saveConfig(_ config: TunnelConfig) throws {
        let data = try encoder.encode(config.pinned())
        try writeAtomically(data: data, to: Paths.configFile, permissions: 0o660)
    }

    public static func loadStatus() -> TunnelStatus {
        guard let data = FileManager.default.contents(atPath: Paths.statusFile),
              let status = try? JSONDecoder().decode(TunnelStatus.self, from: data) else {
            return TunnelStatus()
        }
        return status
    }

    public static func saveStatus(_ status: TunnelStatus) throws {
        let data = try encoder.encode(status)
        try writeAtomically(data: data, to: Paths.statusFile, permissions: 0o664)
    }

    /// Запись через временный файл в том же каталоге + rename, чтобы читатель
    /// никогда не увидел половину JSON.
    public static func writeAtomically(data: Data, to path: String, permissions: Int16) throws {
        let fm = FileManager.default
        let directory = (path as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
            throw ConfigStoreError.directoryMissing
        }
        guard fm.isWritableFile(atPath: directory) else {
            throw ConfigStoreError.notWritable(directory)
        }
        let tempPath = directory + "/.\((path as NSString).lastPathComponent).tmp"
        if fm.fileExists(atPath: tempPath) {
            try? fm.removeItem(atPath: tempPath)
        }
        guard fm.createFile(atPath: tempPath,
                            contents: data,
                            attributes: [.posixPermissions: NSNumber(value: permissions)]) else {
            throw ConfigStoreError.io("Не удалось записать \(tempPath).")
        }
        do {
            if fm.fileExists(atPath: path) {
                _ = try fm.replaceItemAt(URL(fileURLWithPath: path),
                                         withItemAt: URL(fileURLWithPath: tempPath))
            } else {
                try fm.moveItem(atPath: tempPath, toPath: path)
            }
        } catch {
            try? fm.removeItem(atPath: tempPath)
            throw ConfigStoreError.io("Не удалось сохранить \(path): \(error.localizedDescription)")
        }
        try? fm.setAttributes([.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: path)
    }
}
