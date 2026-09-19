package kz.qpvpn.vpn

/**
 * Сторож связи: замечает, что туннель поднят, а сервера за ним уже нет.
 *
 * Признак один: телефон шлёт, а в ответ тишина. Именно так выглядит переезд
 * с Wi-Fi на мобильную сеть — туннель на месте, пакеты уходят, обратно не
 * приходит ничего.
 *
 * По времени последнего рукопожатия это определять нельзя. Лежащий в кармане
 * телефон не обновляет сессию, потому что ему нечего слать, — и приложение
 * поднимало туннель заново каждые две минуты простоя. Связь при этом каждый
 * раз рвалась на секунду-другую, и всё казалось тормозным на ровном месте.
 */
class LinkWatch(
    /** Столько ждём ответа, пока шлём, прежде чем считать связь оборванной. */
    private val silenceMillis: Long = 45_000,

    /** Не чаще этого пересоздаём туннель, чтобы не биться в закрытую дверь. */
    private val repairPauseMillis: Long = 120_000,
) {

    private var lastRx = 0L
    private var lastTx = 0L
    private var rxMovedAt = 0L
    private var lastRepair = 0L

    /** Туннель только что поднялся: считаем отсчёт заново. */
    fun start(rx: Long, tx: Long, now: Long) {
        lastRx = rx
        lastTx = tx
        rxMovedAt = now
        // Пауза между починками отсчитывается от прошлой починки, а её не
        // было: иначе первую пришлось бы ждать лишние две минуты.
        lastRepair = now - repairPauseMillis
    }

    /**
     * Пора ли поднимать туннель заново.
     *
     * Возвращает true не чаще, чем раз в [repairPauseMillis]: если сервер
     * недоступен совсем, бесконечные попытки только сажают батарею.
     */
    fun stalled(rx: Long, tx: Long, now: Long): Boolean {
        if (rx > lastRx) rxMovedAt = now
        val sending = tx > lastTx
        lastRx = rx
        lastTx = tx

        if (!sending) return false
        if (now - rxMovedAt < silenceMillis) return false
        if (now - lastRepair < repairPauseMillis) return false

        lastRepair = now
        return true
    }
}
