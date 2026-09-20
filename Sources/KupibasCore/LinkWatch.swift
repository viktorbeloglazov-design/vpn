import Foundation

/// Сторож связи: замечает, что туннель поднят, а сервера за ним уже нет.
///
/// Признак один: компьютер шлёт, а в ответ тишина. Именно так выглядит
/// переезд с Wi-Fi на другую сеть или пробуждение из сна — интерфейс на
/// месте, пакеты уходят, обратно не приходит ничего.
///
/// По времени последнего handshake это определять нельзя. Простаивающий
/// туннель сессию не обновляет, потому что ему нечего слать, — и служба
/// пересоздавала его каждые три минуты простоя. Связь при этом рвалась,
/// открытые соединения обрывались, и всё казалось тормозным на ровном месте.
public final class LinkWatch {

    /// Столько ждём ответа, пока шлём, прежде чем считать связь оборванной.
    private let silence: TimeInterval

    /// Не чаще этого пересоздаём туннель, чтобы не биться в закрытую дверь.
    private let repairPause: TimeInterval

    private var lastRx = 0
    private var lastTx = 0
    private var rxMovedAt: TimeInterval = 0
    private var lastRepair: TimeInterval = 0

    public init(silence: TimeInterval = 45, repairPause: TimeInterval = 120) {
        self.silence = silence
        self.repairPause = repairPause
    }

    /// Туннель только что поднялся: считаем отсчёт заново.
    public func start(rx: Int, tx: Int, now: TimeInterval) {
        lastRx = rx
        lastTx = tx
        rxMovedAt = now
        // Пауза между починками отсчитывается от прошлой починки, а её не
        // было: иначе первую пришлось бы ждать лишние две минуты.
        lastRepair = now - repairPause
    }

    /// Пора ли поднимать туннель заново.
    public func stalled(rx: Int, tx: Int, now: TimeInterval) -> Bool {
        if rx > lastRx { rxMovedAt = now }
        let sending = tx > lastTx
        lastRx = rx
        lastTx = tx

        guard sending else { return false }
        guard now - rxMovedAt >= silence else { return false }
        guard now - lastRepair >= repairPause else { return false }

        lastRepair = now
        return true
    }
}
