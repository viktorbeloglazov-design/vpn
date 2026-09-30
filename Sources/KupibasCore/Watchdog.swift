import Foundation

/// Сторож живости службы: замечает, что она перестала работать, но не умерла.
///
/// Так выглядела поломка, из-за которой человек шёл переустанавливать
/// службу по нескольку раз за час. Служба раз в секунду сверяет состояние
/// сети и для этого спрашивает систему: `wg show`, `networksetup`,
/// `route`, имена у DNS. Любой такой вопрос может остаться без ответа —
/// система под нагрузкой, сеть переключается, DNS молчит. Тогда цикл
/// встаёт: туннель не поддерживается, состояние не публикуется, связь
/// пропадает.
///
/// Для launchd при этом всё в порядке: процесс жив, перезапускать нечего.
/// Сам себя цикл тоже не вытащит — он и есть то, что зависло. Помогал
/// только человек с кнопкой «переустановить службу».
///
/// Сторож живёт в отдельном потоке и смотрит на одно: давно ли служба
/// подавала признаки жизни. Давно — значит встала, и её надо
/// перезапустить. Она работает от root, так что ей достаточно
/// завершиться: launchd поднимет её через пять секунд, и человеку
/// не нужно ничего нажимать.
///
/// Признак жизни — не «прошёл круг», а «закончилось очередное дело».
/// Разница важная. Подъём туннеля в плохой сети честно занимает
/// несколько минут: подобрать размер пакета, переставить DNS у каждой
/// сетевой службы, проложить тысячи маршрутов. Считай сторож по кругу —
/// он убивал бы службу посреди работы, она начинала бы подъём заново
/// и снова не успевала. Получилась бы ровно та поломка, от которой
/// он поставлен. Поэтому долгая работа, состоящая из коротких дел,
/// сторожа не тревожит, а одно дело, которое не кончается, — тревожит.
public final class Watchdog {

    /// Сколько ждём одно дело, прежде чем считать службу зависшей.
    ///
    /// Больше самого долгого честного ожидания: команды службе
    /// отпущено не больше минуты, проверке связи — меньше. И заведомо
    /// меньше, чем человек станет терпеть без связи.
    public static let defaultLimit: TimeInterval = 90

    public struct Verdict: Equatable {
        /// Пора перезапускать службу.
        public let stuck: Bool
        /// На чём она стоит — для журнала.
        public let stage: String
        /// Сколько секунд уже стоит.
        public let seconds: Int

        public init(stuck: Bool, stage: String, seconds: Int) {
            self.stuck = stuck
            self.stage = stage
            self.seconds = seconds
        }
    }

    private let limit: TimeInterval
    private let lock = NSLock()

    /// Когда служба последний раз подала признак жизни.
    private var aliveAt: TimeInterval

    /// Что делаем прямо сейчас и с какого момента.
    private var stage = ""
    private var stageSince: TimeInterval = 0

    public init(limit: TimeInterval = Watchdog.defaultLimit, now: TimeInterval) {
        self.limit = limit
        self.aliveAt = now
    }

    /// Круг пройден: служба жива.
    public func progress(now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        aliveAt = now
    }

    /// Начали дело, которое может не вернуться.
    public func begin(_ what: String, now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        stage = what
        stageSince = now
    }

    /// Дело закончилось — неважно, чем. Это тоже признак жизни.
    public func end(now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        stage = ""
        stageSince = 0
        aliveAt = now
    }

    /// Не пора ли перезапускаться.
    public func check(now: TimeInterval) -> Verdict {
        lock.lock()
        defer { lock.unlock() }

        // Считаем от начала дела, если оно идёт: иначе долгое дело,
        // начатое сразу после признака жизни, получило бы лишнюю фору.
        let since = stage.isEmpty ? aliveAt : min(aliveAt, stageSince)
        let waiting = now - since
        guard waiting >= limit else {
            return Verdict(stuck: false, stage: stage, seconds: Int(waiting))
        }

        // Называем дело: по нему видно, кто именно не отвечает. Дела нет —
        // значит встал сам цикл, и это тоже надо сказать.
        return Verdict(stuck: true,
                       stage: stage.isEmpty ? "цикл службы" : stage,
                       seconds: Int(waiting))
    }
}
