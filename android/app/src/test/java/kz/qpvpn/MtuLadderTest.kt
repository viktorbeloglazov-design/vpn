package kz.qpvpn

import kz.qpvpn.model.AppConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Подбор размера пакета: с чего начинаем и куда спускаемся.
 *
 * Симптом неподходящего размера узнаваемый: сообщения отправляются, а
 * видео крутится и не скачивается. Мелкое пролезает, крупное — нет.
 */
class MtuLadderTest {

    private val ladder = listOf(1420, 1380, 1320, 1280)

    /** Тот же расчёт, что делает туннель. */
    private fun steps(keyMtu: Int, remembered: Int): List<Int> {
        val start = if (remembered > 0) remembered else minOf(keyMtu, ladder.first())
        return (listOf(start) + ladder.filter { it < start }).distinct()
    }

    @Test
    fun startsFromTheKeyAndGoesDown() {
        assertEquals(listOf(1420, 1380, 1320, 1280), steps(keyMtu = 1420, remembered = 0))
    }

    @Test
    fun keyWithSmallPacketIsNotRaised() {
        // Если в ключе уже 1280, поднимать выше нельзя: сервер настроен так.
        assertEquals(listOf(1280), steps(keyMtu = 1280, remembered = 0))
    }

    @Test
    fun keyAboveTheCeilingIsClamped() {
        // 1500 в туннеле не бывает: заголовки съедают место.
        assertEquals(listOf(1420, 1380, 1320, 1280), steps(keyMtu = 1500, remembered = 0))
    }

    @Test
    fun rememberedValueGoesFirst() {
        // Сеть обычно та же — перебирать всё заново незачем.
        assertEquals(listOf(1320, 1280), steps(keyMtu = 1420, remembered = 1320))
    }

    @Test
    fun theLadderNeverRepeatsItself() {
        for (key in listOf(1280, 1320, 1380, 1420, 1500)) {
            for (remembered in listOf(0, 1280, 1320, 1380, 1420)) {
                val steps = steps(key, remembered)
                assertEquals("повтор в подборе: $steps", steps.distinct().size, steps.size)
                assertTrue("подбор обязан кончаться нижней ступенью: $steps", steps.last() >= 1280)
            }
        }
    }

    @Test
    fun autoIsTheDefault() {
        assertEquals("по умолчанию размер подбирается сам", 0, AppConfig().options.mtu)
        assertEquals("подобранного ещё нет", 0, AppConfig().options.probedMtu)
    }

    @Test
    fun probedValueSurvivesPinning() {
        // Маршрутизация зашита, а подобранный размер — это не маршрутизация.
        val config = AppConfig().let { it.copy(options = it.options.copy(probedMtu = 1320)) }
        assertEquals(1320, config.pinned().options.probedMtu)
    }
}
