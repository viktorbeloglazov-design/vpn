import Foundation
import KupibasCore

/// Поднимает и опускает туннель своими руками, без wg-quick.
///
/// wg-quick на macOS — это скрипт на bash, и ему нужен bash 4+. Система
/// поставляет bash 3.2 и другого не будет: скрипт останавливается на
/// «Version mismatch: bash 3 detected, when bash 4+ required», и туннель не
/// поднимается вовсе. Требовать от человека Homebrew ради одного скрипта
/// неправильно — всё, что он делает, укладывается в несколько вызовов
/// ifconfig, route и networksetup.
///
/// Делать это самим ещё и надёжнее: wg-quick попутно заводит фоновый
/// сторож маршрутов и трогает DNS всех сетевых служб, а маршрутами и так
/// распоряжается служба.
enum WireGuardInterface {

    /// Туда и утилита управления, и сам туннель кладут свои сокеты.
    static let socketDir = "/var/run/amneziawg"

    /// Файл, куда туннель записывает доставшееся ему имя utun.
    static func nameFile(_ logicalName: String) -> String {
        "\(socketDir)/\(logicalName).name"
    }

    static func socketFile(_ interfaceName: String) -> String {
        "\(socketDir)/\(interfaceName).sock"
    }

    // MARK: - Подъём

    /// Создаёт туннель и возвращает настоящее имя интерфейса (utunN).
    static func start(logicalName: String) -> Result<String, String> {
        try? FileManager.default.createDirectory(atPath: socketDir,
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: NSNumber(value: Int16(0o755))])
        // Имя от прошлого запуска собьёт нас с толку: его не должно быть.
        try? FileManager.default.removeItem(atPath: nameFile(logicalName))

        guard let tunnel = Shell.which("amneziawg-go") ?? Shell.which("wireguard-go") else {
            return .failure("Не найден amneziawg-go — переустановите службу из приложения.")
        }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Shell.pathEnvironment
        environment["LANG"] = "C"
        environment["WG_TUN_NAME_FILE"] = nameFile(logicalName)

        if let failure = launch(tunnel, environment: environment) {
            return .failure(failure)
        }

        // Имя и сокет появляются не мгновенно: туннель сначала заводит
        // устройство, и только потом уходит в фон.
        guard let name = waitForName(logicalName: logicalName, seconds: 10) else {
            return .failure("Туннель создан, но интерфейс не появился за 10 секунд.")
        }
        return .success(name)
    }

    /// Куда туннель пишет свои жалобы: читаем их, если он не поднялся.
    private static let logPath = Paths.runtimeDir + "/tunnel.log"

    /// Запускает туннель и ждёт только родительский процесс.
    ///
    /// Туннель уходит в фон сам, поэтому вывод нельзя забирать через канал:
    /// ушедший в фон процесс держал бы его открытым, и чтение ждало бы конца
    /// работы туннеля. Пишем вывод в файл — и читаем оттуда при неудаче.
    private static func launch(_ executable: String, environment: [String: String]) -> String? {
        try? FileManager.default.createDirectory(atPath: Paths.runtimeDir,
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: NSNumber(value: Int16(0o700))])
        FileManager.default.createFile(atPath: logPath, contents: nil,
                                       attributes: [.posixPermissions: NSNumber(value: Int16(0o600))])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["utun"]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        if let handle = FileHandle(forWritingAtPath: logPath) {
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        do {
            try process.run()
        } catch {
            return "не удалось запустить туннель: \(error.localizedDescription)"
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let details = (try? String(contentsOfFile: logPath, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return details.isEmpty
                ? "туннель не запустился (код \(process.terminationStatus))"
                : "туннель не запустился: \(details.suffix(300))"
        }
        return nil
    }

    private static func waitForName(logicalName: String, seconds: Int) -> String? {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            if let data = FileManager.default.contents(atPath: nameFile(logicalName)),
               let text = String(data: data, encoding: .utf8) {
                let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, FileManager.default.fileExists(atPath: socketFile(name)) {
                    return name
                }
            }
            usleep(100_000)
        }
        return nil
    }

    /// Загружает ключи и список AllowedIPs в уже созданный интерфейс.
    static func setConfig(interface: String, text: String) -> CommandResult {
        let path = Paths.runtimeDir + "/setconf.tmp"
        do {
            try ConfigStore.writeAtomically(data: Data(text.utf8), to: path, permissions: 0o600)
        } catch {
            return CommandResult(status: -1, stdout: "",
                                 stderr: "не удалось записать настройки туннеля: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(atPath: path) }
        return Shell.runTool("wg", ["setconf", interface, path], timeout: 20)
    }

    /// Вешает адрес клиента на интерфейс.
    @discardableResult
    static func addAddress(interface: String, address: String) -> CommandResult {
        if address.contains(":") {
            return Shell.runTool("ifconfig", [interface, "inet6", address, "alias"], timeout: 15)
        }
        // Для IPv4 ifconfig хочет и адрес сети, и адрес точки назначения.
        let bare = address.split(separator: "/").first.map(String.init) ?? address
        return Shell.runTool("ifconfig", [interface, "inet", address, bare, "alias"], timeout: 15)
    }

    @discardableResult
    static func setMTU(interface: String, mtu: Int) -> CommandResult {
        Shell.runTool("ifconfig", [interface, "mtu", String(mtu)], timeout: 15)
    }

    @discardableResult
    static func bringUp(interface: String) -> CommandResult {
        Shell.runTool("ifconfig", [interface, "up"], timeout: 15)
    }

    // MARK: - Опускание

    /// Убирает интерфейс: туннель следит за своим сокетом и уходит сам.
    static func stop(interface: String?, logicalName: String) {
        if let interface, !interface.isEmpty {
            try? FileManager.default.removeItem(atPath: socketFile(interface))
            Shell.runTool("ifconfig", [interface, "down"], timeout: 15)
        }
        try? FileManager.default.removeItem(atPath: nameFile(logicalName))
    }

    /// Имя интерфейса, оставшегося от прошлого запуска, если он ещё жив.
    static func existingInterface(logicalName: String) -> String? {
        guard let data = FileManager.default.contents(atPath: nameFile(logicalName)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, FileManager.default.fileExists(atPath: socketFile(name)) else { return nil }
        return name
    }
}
