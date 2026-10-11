import Darwin
import Foundation
import KupibasCore

/// Туннель X-Ray: xray держит соединение с сервером, tun2socks — интерфейс.
///
/// Устройство то же, что у прежнего туннеля, меняется только «двигатель».
/// Служба заводит интерфейс utunN и прокладывает в него те же маршруты
/// (список сервисов, Gmail мимо и прочее). Всё, что туда попало, tun2socks
/// передаёт в socks-вход xray на этом же компьютере, а xray — на сервер.
///
/// Обе программы — дочерние процессы службы. Уйдёт служба — launchd
/// уберёт и их, сирот не остаётся; на всякий случай при запуске служба
/// всё равно добивает остатки по записанным номерам процессов.
enum XrayInterface {

    enum Outcome {
        case started(String)
        case failed(String)
    }

    private static let configPath = Paths.runtimeDir + "/xray.json"
    private static let xrayLog = Paths.runtimeDir + "/xray.log"
    private static let tunLog = Paths.runtimeDir + "/tun2socks.log"
    private static let pidFile = Paths.runtimeDir + "/xray.pids"
    private static let nameFile = Paths.runtimeDir + "/xray.name"

    /// Адрес самого интерфейса. Из диапазона для испытаний (198.18.0.0/15):
    /// ни с чьими настоящими адресами он не пересечётся.
    static let interfaceAddress = "198.18.0.1"

    private static let lock = NSLock()
    private static var xray: Process?
    private static var tun2socks: Process?
    private static var prober: Prober?

    // MARK: - Подъём

    /// Поднимает туннель и возвращает имя интерфейса (utunN).
    ///
    /// - endpoint: host:port, если нужно идти не на адрес из ключа,
    ///   а на запасной вход.
    static func start(link original: XrayLink, endpoint: String? = nil, mtu: Int) -> Outcome {
        guard let xrayPath = Shell.which("xray") else {
            return .failed("Не найден xray — переустановите службу из приложения.")
        }
        guard let tunPath = Shell.which("tun2socks") else {
            return .failed("Не найден tun2socks — переустановите службу из приложения.")
        }
        stop()

        var link = original
        if let endpoint, let parts = Validation.splitEndpoint(endpoint) {
            link.host = parts.host
            link.port = parts.port
        }

        do {
            try FileManager.default.createDirectory(atPath: Paths.runtimeDir,
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: NSNumber(value: Int16(0o700))])
            // В настройках идентификатор — он же пароль. Только для root.
            try ConfigStore.writeAtomically(data: Data(XrayConfig.render(link).utf8),
                                            to: configPath, permissions: 0o600)
        } catch {
            return .failed("Не удалось подготовить настройки X-Ray: \(error.localizedDescription)")
        }

        // Сначала xray: tun2socks бессмысленно поднимать, пока некуда отдавать.
        guard let core = launch(xrayPath, ["run", "-c", configPath], log: xrayLog) else {
            return .failed("xray не запустился: \(tail(xrayLog))")
        }
        guard waitForSocks(seconds: 10) else {
            core.terminate()
            return .failed("xray не открыл вход за 10 секунд: \(tail(xrayLog))")
        }

        let name = freeInterfaceName()
        // Параметры — только в длинной форме: tun2socks разбирает «-loglevel»
        // как связку коротких «-l -o -g…» и отказывается запускаться.
        guard let tun = launch(tunPath, ["--device", name,
                                         "--proxy", "socks5://127.0.0.1:\(XrayConfig.socksPort)",
                                         "--loglevel", "warning"],
                               log: tunLog) else {
            core.terminate()
            return .failed("tun2socks не запустился: \(tail(tunLog))")
        }
        guard waitForInterface(name, seconds: 10) else {
            tun.terminate()
            core.terminate()
            return .failed("Интерфейс \(name) не появился за 10 секунд: \(tail(tunLog))")
        }

        let address = Shell.runTool("ifconfig", [name, "inet", interfaceAddress, interfaceAddress,
                                                 "netmask", "255.255.255.255",
                                                 "mtu", String(mtu), "up"], timeout: 10)
        if !address.succeeded {
            tun.terminate()
            core.terminate()
            return .failed("Интерфейс \(name) не настроился: \(address.failureText)")
        }

        lock.lock()
        xray = core
        tun2socks = tun
        let probe = Prober()
        prober = probe
        lock.unlock()
        probe.start()

        try? "\(core.processIdentifier) \(tun.processIdentifier)"
            .write(toFile: pidFile, atomically: true, encoding: .utf8)
        try? name.write(toFile: nameFile, atomically: true, encoding: .utf8)
        return .started(name)
    }

    /// Переводит xray на другой вход, не трогая интерфейс и маршруты.
    ///
    /// Нужен для запасного входа: сервер молчит — пробуем узел-пересыльщик.
    /// tun2socks при этом продолжает работать, а xray перезапускается
    /// с тем же ключом, но другим адресом.
    static func switchEndpoint(link original: XrayLink, endpoint: String) -> Bool {
        guard let xrayPath = Shell.which("xray"),
              let parts = Validation.splitEndpoint(endpoint) else { return false }
        var link = original
        link.host = parts.host
        link.port = parts.port

        lock.lock()
        let old = xray
        let probe = prober
        lock.unlock()
        old?.terminate()
        let deadline = Date().addingTimeInterval(3)
        while (old?.isRunning ?? false) && Date() < deadline { usleep(100_000) }
        if old?.isRunning ?? false { kill(old!.processIdentifier, SIGKILL) }

        guard (try? ConfigStore.writeAtomically(data: Data(XrayConfig.render(link).utf8),
                                                to: configPath, permissions: 0o600)) != nil,
              let core = launch(xrayPath, ["run", "-c", configPath], log: xrayLog),
              waitForSocks(seconds: 10) else { return false }

        lock.lock()
        xray = core
        lock.unlock()
        probe?.reset()
        if let tunPid = tun2socksPid {
            try? "\(core.processIdentifier) \(tunPid)".write(toFile: pidFile, atomically: true, encoding: .utf8)
        }
        return true
    }

    private static var tun2socksPid: Int32? {
        lock.lock(); defer { lock.unlock() }
        return tun2socks?.processIdentifier
    }

    // MARK: - Опускание

    static func stop() {
        lock.lock()
        let processes = [tun2socks, xray].compactMap { $0 }
        let probe = prober
        xray = nil
        tun2socks = nil
        prober = nil
        lock.unlock()

        probe?.stop()
        for process in processes where process.isRunning {
            process.terminate()
        }
        let deadline = Date().addingTimeInterval(3)
        while processes.contains(where: \.isRunning) && Date() < deadline {
            usleep(100_000)
        }
        for process in processes where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        cleanUpOrphans()
    }

    /// Добивает процессы от прошлого запуска службы.
    static func cleanUpOrphans() {
        if let text = try? String(contentsOfFile: pidFile, encoding: .utf8) {
            for pid in text.split(separator: " ").compactMap({ Int32($0) }) where pid > 1 {
                // Номер мог достаться чужому процессу — проверяем имя.
                let name = processName(pid)
                if name.hasPrefix("xray") || name.hasPrefix("tun2socks") {
                    kill(pid, SIGKILL)
                }
            }
        }
        try? FileManager.default.removeItem(atPath: pidFile)
        try? FileManager.default.removeItem(atPath: nameFile)
    }

    /// Имя интерфейса от прошлого запуска, если он ещё жив.
    static func existingInterface() -> String? {
        guard let name = (try? String(contentsOfFile: nameFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, if_nametoindex(name) > 0 else { return nil }
        return name
    }

    // MARK: - Состояние

    /// Обе программы живы.
    static var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return (xray?.isRunning ?? false) && (tun2socks?.isRunning ?? false)
    }

    /// Когда сервер в последний раз ответил на проверку; 0 — ещё ни разу.
    static var lastAnswer: Double {
        lock.lock(); defer { lock.unlock() }
        return prober?.lastAnswer ?? 0
    }

    /// Счётчики интерфейса: принято (в компьютер) и отправлено (из него).
    static func bytes(interface name: String) -> (rx: Int, tx: Int)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var node: UnsafeMutablePointer<ifaddrs>? = first
        while let current = node {
            if String(cString: current.pointee.ifa_name) == name,
               current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let raw = current.pointee.ifa_data {
                let data = raw.assumingMemoryBound(to: if_data.self).pointee
                // Для utun «вход» — то, что tun2socks отдал компьютеру
                // (ответы сервера), «выход» — то, что программы послали.
                return (Int(data.ifi_ibytes), Int(data.ifi_obytes))
            }
            node = current.pointee.ifa_next
        }
        return nil
    }

    // MARK: - Проверка связи

    /// Раз в пятнадцать секунд спрашивает через туннель маленькую страницу.
    ///
    /// У прежнего протокола было рукопожатие: сервер отвечал на него, и
    /// по времени ответа было видно, жив ли он. У X-Ray рукопожатия нет,
    /// поэтому проверяем делом: запрос через socks-вход уходит на сервер
    /// и возвращается. Ходит в своём потоке: сторож следит за основным
    /// циклом, а запрос через мёртвый сервер может идти секунды.
    private final class Prober {
        private let lock = NSLock()
        private var answer: Double = 0
        private var running = true

        var lastAnswer: Double {
            lock.lock(); defer { lock.unlock() }
            return answer
        }

        func start() {
            let thread = Thread { [weak self] in
                while let self, self.isRunning {
                    if XrayInterface.probe() {
                        self.lock.lock()
                        self.answer = Date().timeIntervalSince1970
                        self.lock.unlock()
                    }
                    for _ in 0..<15 where self.isRunning { Thread.sleep(forTimeInterval: 1) }
                }
            }
            thread.name = "kupibas.xray-probe"
            thread.start()
        }

        func stop() {
            lock.lock(); running = false; lock.unlock()
        }

        /// Забыть прошлые ответы: сервер сменился.
        func reset() {
            lock.lock(); answer = 0; lock.unlock()
        }

        private var isRunning: Bool {
            lock.lock(); defer { lock.unlock() }
            return running
        }
    }

    /// Адреса для проверки: маленькие страницы, которые отдают «204».
    static let probeURLs = [
        "https://www.gstatic.com/generate_204",
        "https://cp.cloudflare.com/generate_204",
    ]

    /// Ответил ли сервер: запрос через socks-вход.
    static func probe() -> Bool {
        for url in probeURLs {
            let result = runQuietly("/usr/bin/curl",
                                    ["-s", "-o", "/dev/null", "-w", "%{http_code}",
                                     "--max-time", "8",
                                     "--socks5-hostname", "127.0.0.1:\(XrayConfig.socksPort)", url],
                                    timeout: 12)
            if result.status == 0, ["204", "200"].contains(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return true
            }
        }
        return false
    }

    // MARK: - Внутреннее

    /// Запускает программу и не ждёт её: она работает, пока жив туннель.
    private static func launch(_ path: String, _ arguments: [String], log: String) -> Process? {
        FileManager.default.createFile(atPath: log, contents: nil,
                                       attributes: [.posixPermissions: NSNumber(value: Int16(0o600))])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Shell.pathEnvironment
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        if let handle = FileHandle(forWritingAtPath: log) {
            process.standardOutput = handle
            process.standardError = handle
        }
        do {
            try process.run()
        } catch {
            return nil
        }
        // Упасть на старте она может сразу — например, не приняв настройки.
        usleep(300_000)
        return process.isRunning ? process : nil
    }

    private static func waitForSocks(seconds: Int) -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            if canConnect(port: XrayConfig.socksPort) { return true }
            usleep(200_000)
        }
        return false
    }

    private static func canConnect(port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private static func waitForInterface(_ name: String, seconds: Int) -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            if if_nametoindex(name) > 0 { return true }
            usleep(100_000)
        }
        return false
    }

    /// Свободное имя utun: свои номера начинаем с 20, чтобы не толкаться
    /// с системными (iCloud, «Связка ключей» заводят utun0…utun5).
    private static func freeInterfaceName() -> String {
        for number in 20..<200 where if_nametoindex("utun\(number)") == 0 {
            return "utun\(number)"
        }
        return "utun250"
    }

    private static func tail(_ path: String) -> String {
        let text = (try? String(contentsOfFile: path, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "причина не записана" : String(text.suffix(300))
    }

    private static func processName(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    /// Свой запуск, а не Shell: Shell рассказывает сторожу о каждой
    /// команде, а проверка идёт в своём потоке.
    private static func runQuietly(_ tool: String, _ arguments: [String],
                                   timeout: TimeInterval) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(100_000) }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
