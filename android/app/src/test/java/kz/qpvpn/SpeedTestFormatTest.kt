package kz.qpvpn

import kz.qpvpn.net.SpeedTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Как показывается результат замера. */
class SpeedTestFormatTest {

    @Test
    fun zeroMeansNotMeasured() {
        assertEquals("—", SpeedTest.format(0.0))
        assertEquals("—", SpeedTest.format(-1.0))
    }

    @Test
    fun slowSpeedKeepsOneDigit() {
        assertTrue(SpeedTest.format(12.34).startsWith("12"))
        assertTrue(SpeedTest.format(12.34).endsWith("Мбит/с"))
    }

    @Test
    fun fastSpeedIsRounded() {
        assertEquals("250 Мбит/с", SpeedTest.format(250.7))
    }

    @Test
    fun veryslowSpeedIsStillVisible() {
        // Ноль означает «не получилось», поэтому очень медленная связь
        // обязана показываться числом, а не превращаться в прочерк.
        assertTrue(SpeedTest.format(0.03) != "—")
    }
}
