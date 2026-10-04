import Foundation
import KupibasCore

/// Служба обновляет себя сама — без пароля и без человека.
///
/// Всё долгое — узнать версию, скачать образ, проверить его — идёт
/// в своём потоке: основной цикл в это время держит туннель, а сторож
/// живости не видит здесь ни одного дела, которое могло бы его встревожить.
/// В основной цикл отдаётся только готовое: папка с проверенными
/// файлами. Подмена — это несколько переименований, доли секунды.
final class Updater {

    struct Ready {
        let version: String
        let from: String
        let dir: String
    }

    private let log: Logger
    private let startedAt = Uptime.seconds()
    private var lastCheck: TimeInterval?
    private var lastFailed = false
    private var reportedNoVersion = false

    private let lock = NSLock()
    private var ready: Ready?

    init(log: Logger) {
        self.log = log
    }

    /// Версия, из которой поставлена служба. nil — отметки нет:
    /// службу собрали руками, и обновлять её нечем сравнивать.
    static var installedVersion: String? {
        guard let text = try? String(contentsOfFile: Paths.helperVersionFile, encoding: .utf8) else {
            return nil
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Versions.isPlausible(value) ? value : nil
    }

    func start() {
        let thread = Thread { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: 30)
                self?.checkIfDue()
            }
        }
        thread.name = "kupibas.updater"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// Забирает готовое обновление. Вызывается из основного цикла.
    func takeReady() -> Ready? {
        lock.lock(); defer { lock.unlock() }
        let value = ready
        ready = nil
        return value
    }

    // MARK: - Проверка

    private func checkIfDue() {
        let fm = FileManager.default
        let requested = fm.fileExists(atPath: SelfUpdate.requestFile)
        if requested { try? fm.removeItem(atPath: SelfUpdate.requestFile) }

        let now = Uptime.seconds()
        guard SelfUpdate.isDue(sinceStart: now - startedAt,
                               sinceLastCheck: lastCheck.map { now - $0 },
                               lastFailed: lastFailed,
                               requested: requested) else { return }
        lastCheck = now

        lock.lock()
        let pending = ready != nil
        lock.unlock()
        guard !pending else { return }

        guard let current = Updater.installedVersion else {
            if !reportedNoVersion {
                log.info("Обновление: у службы нет отметки о версии — сама не обновляюсь.")
                reportedNoVersion = true
            }
            return
        }

        switch prepare(current: current) {
        case .upToDate(let latest):
            lastFailed = false
            if requested { SelfUpdate.writeResult("свежая версия \(latest) уже стоит") }
        case .ready(let value):
            lastFailed = false
            lock.lock(); ready = value; lock.unlock()
            log.info("Обновление \(value.version) скачано и проверено — ставлю.")
        case .failed(let reason):
            lastFailed = true
            log.error("Обновление не удалось: \(reason)")
            SelfUpdate.writeResult("обновить службу не удалось: \(reason)")
        }
    }

    private enum Outcome {
        case upToDate(String)
        case ready(Ready)
        case failed(String)
    }

    private func prepare(current: String) -> Outcome {
        guard let latest = fetchText(SelfUpdate.versionURL), Versions.isPlausible(latest) else {
            return .failed("не узнать свежую версию — нет связи с хранилищем")
        }
        guard Versions.isNewer(latest, than: current) else { return .upToDate(latest) }

        log.info("Вышла версия \(latest), у службы \(current) — скачиваю.")

        let fm = FileManager.default
        let work = SelfUpdate.workDir
        try? fm.removeItem(atPath: work)
        do {
            try fm.createDirectory(atPath: work, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: NSNumber(value: Int16(0o700))])
        } catch {
            return .failed("не создать папку для скачанного: \(error.localizedDescription)")
        }

        let image = work + "/QPVPN.dmg"
        guard download(SelfUpdate.imageURL, to: image) else {
            return .failed("образ не скачался")
        }

        guard let mount = attach(image, mountRoot: work) else {
            return .failed("образ не открылся — возможно, скачался не целиком")
        }
        defer {
            _ = run("/usr/bin/hdiutil", ["detach", mount, "-force", "-quiet"], timeout: 60)
            try? fm.removeItem(atPath: image)
        }

        let app = mount + "/QPVPN.app"
        let info = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")
        let helpers = app + "/Contents/Library/Helpers"
        let present = Set(SelfUpdate.helperFiles.filter { fm.isExecutableFile(atPath: helpers + "/" + $0) })

        if let problem = SelfUpdate.problem(
            bundleIdentifier: info?["CFBundleIdentifier"] as? String,
            bundleVersion: info?["CFBundleShortVersionString"] as? String,
            expectedVersion: latest,
            presentHelperFiles: present) {
            return .failed(problem)
        }

        // Подпись у сборки своя, без сертификата Apple, — кто подписал,
        // она не скажет. Но испорченный или подменённый по дороге файл
        // она не пропустит.
        let signature = run("/usr/bin/codesign", ["--verify", "--strict", app], timeout: 120)
        guard signature.status == 0 else {
            return .failed("подпись приложения в образе не сходится")
        }

        let staged = work + "/\(latest)"
        do {
            try fm.createDirectory(atPath: staged, withIntermediateDirectories: true)
            for name in present {
                try fm.copyItem(atPath: helpers + "/" + name, toPath: staged + "/" + name)
                chmod(staged + "/" + name, 0o755)
            }
            let resources = app + "/Contents/Resources"
            for name in ["ru_ipv4.txt", Paths.daemonLabel + ".plist"]
            where fm.fileExists(atPath: resources + "/" + name) {
                try fm.copyItem(atPath: resources + "/" + name, toPath: staged + "/" + name)
            }
        } catch {
            return .failed("не скопировать файлы из образа: \(error.localizedDescription)")
        }

        // Последняя проверка: новая служба на этом Mac хотя бы запускается.
        // Иначе мы бы заменили работающую службу неработающей.
        let check = run(staged + "/kupibasvpnd", ["--check"], timeout: 30)
        guard check.status == 0 else {
            return .failed("новая служба не запускается на этом Mac")
        }

        return .ready(Ready(version: latest, from: current, dir: staged))
    }

    // MARK: - Подмена

    /// Ставит проверенные файлы на место. Вызывается из основного цикла.
    ///
    /// Каждый файл встаёт одним переименованием: работающая служба
    /// продолжает исполнять старую копию, пока не выйдет, а launchd
    /// поднимет уже новую. Возвращает false, если подменить не вышло —
    /// тогда работает прежняя версия, как будто ничего не было.
    func apply(_ ready: Ready) -> Bool {
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: SelfUpdate.workDir) }

        // Сначала сама служба: не встала она — не трогаем и остальное.
        let order = ["kupibasvpnd"] + SelfUpdate.helperFiles.filter { $0 != "kupibasvpnd" }
        for name in order {
            let source = ready.dir + "/" + name
            guard fm.fileExists(atPath: source) else { continue }
            if rename(source, Paths.helperDir + "/" + name) != 0 {
                let reason = String(cString: strerror(errno))
                if name == "kupibasvpnd" {
                    SelfUpdate.writeResult("обновить службу не удалось: не заменить файл (\(reason))")
                    log.error("Обновление: не заменить kupibasvpnd — \(reason). Остаюсь на \(ready.from).")
                    return false
                }
                log.error("Обновление: не заменить \(name) — \(reason).")
            }
        }

        replaceFile(ready.dir + "/ru_ipv4.txt", at: RuZone.installedPath)

        // Файл регистрации launchd читает только при загрузке службы,
        // то есть после перезагрузки Mac. Кладём его, если он поменялся.
        let plist = ready.dir + "/" + Paths.daemonLabel + ".plist"
        if let fresh = fm.contents(atPath: plist), fresh != fm.contents(atPath: Paths.daemonPlist) {
            replaceFile(plist, at: Paths.daemonPlist)
        }

        try? ready.version.write(toFile: Paths.helperVersionFile, atomically: true, encoding: .utf8)
        chmod(Paths.helperVersionFile, 0o644)

        SelfUpdate.writeResult("служба сама обновилась с \(ready.from) до \(ready.version)")
        return true
    }

    /// Кладёт файл на место одним переименованием.
    private func replaceFile(_ source: String, at target: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source) else { return }
        let temporary = target + ".new"
        try? fm.removeItem(atPath: temporary)
        do {
            try fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent,
                                   withIntermediateDirectories: true)
            try fm.copyItem(atPath: source, toPath: temporary)
            chmod(temporary, 0o644)
            if rename(temporary, target) != 0 {
                log.error("Обновление: не заменить \(target) — \(String(cString: strerror(errno))).")
                try? fm.removeItem(atPath: temporary)
            }
        } catch {
            log.error("Обновление: не положить \(target) — \(error.localizedDescription).")
        }
    }

    // MARK: - Сеть

    /// Скачивание идёт программой curl, а не URLSession: ей можно велеть
    /// идти мимо туннеля.
    ///
    /// github.com в списке «через VPN» — ради Copilot. Пока сервер
    /// отвечает, это не мешает. Но если туннель поднят, а сервер молчит,
    /// служба не может скачать то самое обновление, которое её починит:
    /// в CI так и вышло — «нет связи с хранилищем» при поднятом туннеле.
    /// Поэтому при неудаче — вторая попытка, привязанная к физическому
    /// интерфейсу (Wi-Fi или кабелю): такой запрос в туннель не попадает.
    private func curl(_ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String) {
        let common = ["-fsSL", "--retry", "2", "--connect-timeout", "15"]
        let first = run("/usr/bin/curl", common + arguments, timeout: timeout)
        guard first.status != 0, let physical = physicalInterface() else { return first }
        log.info("Обновление: напрямую не вышло, пробую мимо туннеля через \(physical).")
        return run("/usr/bin/curl", common + ["--interface", physical] + arguments, timeout: timeout)
    }

    /// Интерфейс, через который Mac выходит в интернет сам, без туннеля.
    private func physicalInterface() -> String? {
        let result = run("/sbin/route", ["-n", "get", "default"], timeout: 10)
        guard result.status == 0 else { return nil }
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count == 2, parts[0] == "interface", !parts[1].isEmpty,
               !RouteGuard.isTunnel(interface: parts[1]) {
                return parts[1]
            }
        }
        return nil
    }

    private func fetchText(_ url: URL) -> String? {
        let result = curl(["--max-time", "30", "-H", "Cache-Control: no-cache", url.absoluteString],
                          timeout: 90)
        guard result.status == 0 else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func download(_ url: URL, to path: String) -> Bool {
        try? FileManager.default.removeItem(atPath: path)
        let result = curl(["--max-time", "600", "-o", path, url.absoluteString], timeout: 1300)
        return result.status == 0 && FileManager.default.fileExists(atPath: path)
    }

    private final class Box<T> {
        private let lock = NSLock()
        private var stored: T?
        var value: T? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }

    // MARK: - Образ

    /// Подключает образ в свою папку, не показывая его на столе.
    private func attach(_ image: String, mountRoot: String) -> String? {
        let result = run("/usr/bin/hdiutil",
                         ["attach", image, "-nobrowse", "-readonly", "-noautoopen",
                          "-mountrandom", mountRoot, "-plist"],
                         timeout: 180)
        guard result.status == 0,
              let plist = try? PropertyListSerialization.propertyList(
                  from: Data(result.output.utf8), options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else { return nil }

        // Точка монтирования есть только у записи с файловой системой.
        for entity in entities {
            if let point = entity["mount-point"] as? String, !point.isEmpty { return point }
        }
        return nil
    }

    /// Свой запуск команд, а не Shell: Shell рассказывает сторожу о каждой
    /// команде, а сторож следит за основным циклом, не за этим потоком.
    private func run(_ tool: String, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do { try process.run() } catch { return (-1, "") }

        let output = Box<Data>()
        let reader = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output.value = pipe.fileHandleForReading.readDataToEndOfFile()
            reader.signal()
        }

        let deadline = Uptime.seconds() + timeout
        while process.isRunning && Uptime.seconds() < deadline { usleep(100_000) }
        if process.isRunning {
            process.terminate()
            usleep(300_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        _ = reader.wait(timeout: .now() + 5)
        return (process.terminationStatus, String(data: output.value ?? Data(), encoding: .utf8) ?? "")
    }
}
