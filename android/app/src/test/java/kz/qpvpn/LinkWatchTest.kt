package kz.qpvpn

import kz.qpvpn.vpn.LinkWatch
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Когда туннель поднимать заново, а когда не трогать.
 *
 * Прежняя проверка смотрела на возраст рукопожатия и потому пересоздавала
 * туннель каждые две минуты простоя — связь дёргалась на ровном месте.
 */
class LinkWatchTest {

    private val second = 1_000L
    private val minute = 60_000L

    @Test
    fun idlePhoneIsNeverTouched() {
        // Телефон лежит в кармане: ни отправки, ни приёма. Час подряд.
        val watch = LinkWatch()
        var now = 0L
        watch.start(rx = 1_000, tx = 1_000, now = now)

        repeat(1_800) {
            now += 2 * second
            assertFalse(
                "простой не повод рвать связь (прошло ${now / minute} мин)",
                watch.stalled(rx = 1_000, tx = 1_000, now = now),
            )
        }
    }

    @Test
    fun workingTunnelIsNeverTouched() {
        // Обычная работа: ушло и пришло.
        val watch = LinkWatch()
        var now = 0L
        var rx = 0L
        var tx = 0L
        watch.start(rx, tx, now)

        repeat(1_800) {
            now += 2 * second
            rx += 40_000
            tx += 8_000
            assertFalse("рабочий туннель трогать нельзя", watch.stalled(rx, tx, now))
        }
    }

    @Test
    fun silenceWhileSendingIsCaught() {
        // Переезд с Wi-Fi на мобильную сеть: шлём, в ответ тишина.
        val watch = LinkWatch()
        var now = 0L
        var tx = 0L
        watch.start(rx = 5_000, tx = tx, now = now)

        var caught = false
        repeat(40) {
            now += 2 * second
            tx += 1_500
            if (watch.stalled(rx = 5_000, tx = tx, now = now)) caught = true
        }

        assertTrue("оборванную связь надо чинить", caught)
    }

    @Test
    fun silenceIsGivenTimeBeforeReconnecting() {
        // Полминуты без ответа — ещё не повод: так бывает на слабом сигнале.
        val watch = LinkWatch()
        var now = 0L
        var tx = 0L
        watch.start(rx = 5_000, tx = tx, now = now)

        repeat(15) {
            now += 2 * second
            tx += 1_500
            assertFalse("30 секунд тишины — рано (${now / second} с)", watch.stalled(5_000, tx, now))
        }
    }

    @Test
    fun repairsAreNotRepeatedInARow() {
        // Сервер лежит: чинить каждые две секунды бессмысленно, сядет батарея.
        val watch = LinkWatch()
        var now = 0L
        var tx = 0L
        watch.start(rx = 5_000, tx = tx, now = now)

        var repairs = 0
        repeat(300) {
            now += 2 * second
            tx += 1_500
            if (watch.stalled(5_000, tx, now)) repairs++
        }

        // Десять минут: одна починка примерно в две минуты.
        assertTrue("починок должно быть немного, а их $repairs", repairs in 1..6)
    }

    @Test
    fun answerResetsTheCountdown() {
        // Ответ пришёл — отсчёт тишины начинается заново.
        val watch = LinkWatch()
        var now = 0L
        var rx = 5_000L
        var tx = 0L
        watch.start(rx, tx, now)

        repeat(100) {
            now += 2 * second
            tx += 1_500
            // Ответ раз в 40 секунд: редко, но связь жива.
            if (now % 40_000L == 0L) rx += 500
            assertFalse("связь отвечает — трогать нечего", watch.stalled(rx, tx, now))
        }
    }
}
