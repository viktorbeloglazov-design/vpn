package kz.qpvpn

import kz.qpvpn.net.UpdateCheck
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Сравнение версий: что считать обновлением.
 *
 * По буквам «1.2.10» оказалось бы меньше «1.2.9», и обновление до десятой
 * сборки человек бы не увидел — поэтому сравниваем числами по частям.
 */
class UpdateCheckTest {

    @Test
    fun higherNumberWins() {
        assertTrue(UpdateCheck.isNewer("2.7.0", "2.6.0"))
        assertTrue(UpdateCheck.isNewer("3.0.0", "2.9.9"))
        assertTrue(UpdateCheck.isNewer("2.6.1", "2.6.0"))
    }

    @Test
    fun tenIsNewerThanNine() {
        assertTrue(UpdateCheck.isNewer("1.2.10", "1.2.9"))
        assertTrue(UpdateCheck.isNewer("1.10.0", "1.9.0"))
        assertTrue(UpdateCheck.isNewer("10.0.0", "9.0.0"))
    }

    @Test
    fun sameVersionIsNotAnUpdate() {
        assertFalse(UpdateCheck.isNewer("2.6.0", "2.6.0"))
    }

    @Test
    fun olderIsNotAnUpdate() {
        assertFalse(UpdateCheck.isNewer("2.5.0", "2.6.0"))
        assertFalse(UpdateCheck.isNewer("1.2.9", "1.2.10"))
    }

    @Test
    fun missingPartsCountAsZero() {
        assertTrue(UpdateCheck.isNewer("2.7", "2.6.9"))
        assertFalse(UpdateCheck.isNewer("2.6", "2.6.0"))
        assertTrue(UpdateCheck.isNewer("2.6.1", "2.6"))
    }
}
