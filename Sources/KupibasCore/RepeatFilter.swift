import Foundation

/// Не даёт одной и той же записи забить журнал.
///
/// В журнале с Mac строка «Маршрута по умолчанию нет вовсе» повторялась
/// каждые семнадцать секунд часами — это тысячи одинаковых строк за сутки.
/// Вреда от них больше, чем пользы: журнал ограничен двумя мегабайтами,
/// и при переполнении он обрезался, унося с собой начало истории — ровно
/// то место, где видно, с чего всё началось.
///
/// Поэтому повтор подряд пишется не сразу, а с задержкой, и сообщает,
/// сколько раз повторился. Разные записи друг друга не задерживают:
/// новая строка всегда проходит сразу.
public struct RepeatFilter {

    /// Как часто повторять одну и ту же запись.
    public static let pause: TimeInterval = 600

    private let pause: TimeInterval
    private var last = ""
    private var lastAt: TimeInterval = 0
    private var skipped = 0

    public init(pause: TimeInterval = RepeatFilter.pause) {
        self.pause = pause
    }

    /// Что записать в журнал. Пусто — эту запись сейчас пропускаем.
    public mutating func passing(_ message: String, now: TimeInterval) -> String? {
        guard message == last else {
            // Новая запись. Если предыдущая повторялась молча — скажем,
            // сколько раз, иначе счёт пропадёт незаметно.
            let tail = skipped > 0 ? "(предыдущая строка повторилась ещё \(skipped) раз)\n" : ""
            last = message
            lastAt = now
            skipped = 0
            return tail + message
        }

        guard now - lastAt >= pause else {
            skipped += 1
            return nil
        }

        let text = skipped > 0
            ? "\(message) (повторилось ещё \(skipped) раз)"
            : message
        lastAt = now
        skipped = 0
        return text
    }
}
