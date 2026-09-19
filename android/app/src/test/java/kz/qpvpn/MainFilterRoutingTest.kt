package kz.qpvpn

import kz.qpvpn.model.AppConfig
import kz.qpvpn.model.TunnelMode
import kz.qpvpn.net.Cidr
import kz.qpvpn.net.Ipv4Net
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Главный фильтр на настоящем списке подсетей России.
 *
 * Проверяется то, ради чего он переделан: заблокированный сервис попадает
 * в туннель, даже если его адрес приложению незнаком, а российские адреса
 * остаются снаружи. Раньше фильтр разворачивал имена в адреса — и ломался
 * о подменённый DNS.
 */
class MainFilterRoutingTest {

    private val ruZone: List<Ipv4Net> by lazy {
        File("src/main/res/raw/ru_ipv4.txt").readLines()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .mapNotNull { Cidr.parse(it) }
    }

    /** Маршруты туннеля при включённом главном фильтре. */
    private val tunnelRoutes: List<Ipv4Net> by lazy { Cidr.complement(ruZone) }

    private fun inTunnel(address: String): Boolean {
        val net = Cidr.parse(address) ?: error("«$address» не разобрался")
        return tunnelRoutes.any { net.start >= it.start && net.start <= it.endInclusive }
    }

    @Test
    fun ruZoneListIsLoaded() {
        assertTrue("список России не прочитался: ${ruZone.size}", ruZone.size > 8_000)
    }

    @Test
    fun blockedServicesGoThroughTunnel() {
        // Ни одного из этих адресов приложение заранее не знает — и не должно.
        listOf(
            "157.240.229.35" to "Facebook",
            "142.250.185.110" to "Google",
            "104.244.42.1" to "Twitter",
            "13.107.42.14" to "Microsoft",
            "104.18.32.47" to "Cloudflare",
        ).forEach { (address, name) ->
            assertTrue("$name ($address) должен идти через VPN", inTunnel(address))
        }
    }

    @Test
    fun russianServicesGoDirect() {
        listOf(
            "5.255.255.242" to "Яндекс",
            "77.88.8.8" to "Яндекс DNS",
            "87.240.190.78" to "ВКонтакте",
            "194.54.14.131" to "Сбер",
            "2.60.0.1" to "МТС",
        ).forEach { (address, name) ->
            assertFalse("$name ($address) должен идти напрямую", inTunnel(address))
        }
    }

    @Test
    fun tunnelAndBypassCoverEverythingOnce() {
        val tunnel = tunnelRoutes.sumOf { it.size }
        val bypass = Cidr.merge(ruZone).sumOf { it.size }
        assertEquals("вместе должны покрывать всё адресное пространство ровно один раз", 1L shl 32, tunnel + bypass)
    }

    @Test
    fun bypassIsSmallPartOfInternet() {
        // Если бы список внезапно раздулся, мимо VPN ушло бы пол-интернета —
        // и фильтр перестал бы работать незаметно.
        val bypass = Cidr.merge(ruZone).sumOf { it.size }
        val share = bypass.toDouble() / (1L shl 32)
        assertTrue("мимо туннеля уходит $share адресного пространства — это слишком много", share < 0.05)
    }

    @Test
    fun defaultConfigUsesThisRouting() {
        assertEquals(TunnelMode.EXCLUDE, AppConfig().effectiveMode)
    }
}
