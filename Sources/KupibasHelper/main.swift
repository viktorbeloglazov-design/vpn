import Foundation
import KupibasCore

// kupibasvpnd — привилегированная служба Kupibas VPN.
// Запускается launchd от root, раз в секунду сверяет config.json с реальным
// состоянием сети и публикует status.json для интерфейса.

setvbuf(stdout, nil, _IOLBF, 0)

// Проверка работоспособности файла: установщик так убеждается, что бинарник
// вообще запускается на этой машине, до регистрации в launchd.
if CommandLine.arguments.contains("--check") {
    print("kupibasvpnd готов к запуску")
    exit(0)
}

let log = Logger(path: Paths.logFile)

guard getuid() == 0 else {
    FileHandle.standardError.write(Data("kupibasvpnd должен запускаться от root (через launchd).\n".utf8))
    exit(1)
}

// Каталог состояния: root:staff, 0770 — админ-пользователь может писать config.json.
let fileManager = FileManager.default
if !fileManager.fileExists(atPath: Paths.stateDir) {
    try? fileManager.createDirectory(atPath: Paths.stateDir,
                                     withIntermediateDirectories: true,
                                     attributes: [.posixPermissions: NSNumber(value: Int16(0o770))])
}

// Сторож живости. Служба раз в секунду спрашивает систему о состоянии
// сети, и любой такой вопрос может остаться без ответа: система занята,
// сеть переключается, DNS молчит. Тогда цикл встаёт — туннель не
// поддерживается, связь пропадает, — но процесс жив, и launchd не видит
// повода вмешаться. Человеку оставалось только переустановить службу
// руками, по нескольку раз за час.
let watchdog = Watchdog(now: Uptime.seconds())
Shell.watchdog = watchdog
Resolver.watchdog = watchdog

// За сторожем смотрит отдельный поток. Он ничего не чинит: замечает,
// что служба слишком долго не подавала признаков жизни, называет в
// журнале виновника и завершает её. Launchd поднимет службу через пять
// секунд, и она начнёт с чистого листа — без человека и без пароля.
let guardThread = Thread {
    while true {
        Thread.sleep(forTimeInterval: 5)
        let verdict = watchdog.check(now: Uptime.seconds())
        guard verdict.stuck else { continue }

        log.critical("Служба встала на «\(verdict.stage)» \(verdict.seconds) с назад "
            + "и не отвечает — перезапускаюсь. Launchd поднимет через пять секунд.")
        // Коротко — туда, откуда это попадёт в отчёт диагностики:
        // системный журнал человек читать не станет, а отчёт пришлёт.
        RestartLog.add(stage: verdict.stage, seconds: verdict.seconds)
        // Обычный exit() ждал бы завершения того, что уже зависло.
        // Здесь нужно уйти сразу: журнал записан, остальное доделает
        // новая копия службы, начав с чистого листа.
        _exit(70)
    }
}
guardThread.name = "kupibas.watchdog"
guardThread.start()

let manager = TunnelManager(log: log, watchdog: watchdog)
manager.recoverOnStartup()

let signalQueue = DispatchQueue(label: "kupibas.signals")
var sources: [DispatchSourceSignal] = []
for number in [SIGTERM, SIGINT] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: signalQueue)
    source.setEventHandler {
        log.info("Получен сигнал \(number) — завершаюсь.")
        manager.shutdown()
        exit(0)
    }
    source.resume()
    sources.append(source)
}

log.info("kupibasvpnd запущен.")


while true {
    manager.tick()
    watchdog.progress(now: Uptime.seconds())
    Thread.sleep(forTimeInterval: 1.0)
}
