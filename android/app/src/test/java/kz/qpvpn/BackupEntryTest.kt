package kz.qpvpn

import kz.qpvpn.model.AppConfig
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Запасной вход: куда приложение пробует подключаться и в каком порядке.
 *
 * Сначала сервер напрямую — так короче путь и выше скорость. Узел-пересыльщик
 * нужен только там, где оператор выпускает наружу не все адреса.
 */
class BackupEntryTest {

    private val server = "77.240.39.23:31984"

    @Test
    fun withoutBackupThereIsOnlyTheServer() {
        assertEquals(listOf(server), AppConfig().endpointsToTry(server))
    }

    @Test
    fun serverGoesFirstAndBackupSecond() {
        val config = AppConfig(backupEndpoint = "95.213.0.1:31984")
        assertEquals(
            listOf(server, "95.213.0.1:31984"),
            config.endpointsToTry(server),
        )
    }

    @Test
    fun spacesAroundTheAddressDoNotCount() {
        val config = AppConfig(backupEndpoint = "  95.213.0.1:31984  ")
        assertEquals(
            listOf(server, "95.213.0.1:31984"),
            config.endpointsToTry(server),
        )
    }

    @Test
    fun theSameAddressIsNotTriedTwice() {
        // Иначе при молчащем сервере человек ждал бы вдвое дольше впустую.
        val config = AppConfig(backupEndpoint = server)
        assertEquals(listOf(server), config.endpointsToTry(server))
    }

    @Test
    fun emptyBackupIsIgnored() {
        assertEquals(listOf(server), AppConfig(backupEndpoint = "   ").endpointsToTry(server))
    }

    @Test
    fun backupSurvivesPinning() {
        // Маршрутизация зашита, а адрес входа — это не маршрутизация:
        // он обязан пережить приведение настроек к заводскому виду.
        val config = AppConfig(backupEndpoint = "95.213.0.1:31984").pinned()
        assertEquals("95.213.0.1:31984", config.backupEndpoint)
    }
}
