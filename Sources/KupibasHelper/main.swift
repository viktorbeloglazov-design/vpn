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

let manager = TunnelManager(log: log)
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
    Thread.sleep(forTimeInterval: 1.0)
}
