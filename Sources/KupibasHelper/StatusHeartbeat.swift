import Foundation
import KupibasCore

/// Пульс службы: приложение видит, что она жива, даже пока она занята.
///
/// Состояние пишет основной цикл, раз в секунду. Но подъём и снятие
/// туннеля, смена сети, медленный DNS занимают его на десятки секунд —
/// и всё это время файл состояния не обновлялся. Приложение через
/// пятнадцать секунд тишины пишет «служба не отвечает», хотя служба
/// работает. В CI это видно прямо: снятие туннеля шло 33 секунды,
/// и всё это время служба для приложения «не отвечала».
///
/// Пульс в своём потоке переписывает последнее состояние со свежим
/// временем, если основной цикл давно молчит. Настоящее зависание
/// он не прячет: за ним следит сторож и перезапускает службу.
final class StatusHeartbeat {

    static let shared = StatusHeartbeat()

    /// Через сколько секунд молчания основного цикла подавать голос.
    static let quietAfter: TimeInterval = 4

    private let lock = NSLock()
    private var last: TunnelStatus?
    private var lastWrite = Uptime.seconds()

    /// Запись из основного цикла.
    func write(_ status: TunnelStatus) throws {
        lock.lock(); defer { lock.unlock() }
        try ConfigStore.saveStatus(status)
        last = status
        lastWrite = Uptime.seconds()
    }

    func start() {
        let thread = Thread { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: 2)
                self?.beat()
            }
        }
        thread.name = "kupibas.heartbeat"
        thread.start()
    }

    private func beat() {
        lock.lock(); defer { lock.unlock() }
        guard var status = last, Uptime.seconds() - lastWrite >= Self.quietAfter else { return }
        status.updatedAt = Date().timeIntervalSince1970
        if (try? ConfigStore.saveStatus(status)) != nil {
            lastWrite = Uptime.seconds()
        }
    }
}
