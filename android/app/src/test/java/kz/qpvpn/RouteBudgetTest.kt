package kz.qpvpn

import kz.qpvpn.model.KeepInTunnel
import kz.qpvpn.net.Cidr
import kz.qpvpn.net.Ipv4Net
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Сколько маршрутов уезжает в систему.
 *
 * Точный список России даёт больше двадцати тысяч маршрутов. Android такую
 * посылку не принимает: туннель молча не поднимается, значка VPN нет. Здесь
 * проверяется, что приложение укрупняет список до разумного размера и при
 * этом не выпускает наружу нужные сервисы.
 */
class RouteBudgetTest {

    private val maxRoutes = 4_000
    private val gaps = listOf(4_096L, 16_384L, 65_536L, 262_144L, 1_048_576L)

    private val ruZone: List<Ipv4Net> by lazy {
        File("src/main/res/raw/ru_ipv4.txt").readLines()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .mapNotNull { Cidr.parse(it) }
    }

    /** Тот же расчёт, что делает туннель. */
    private fun fittingZone(): Pair<List<Ipv4Net>, Int> {
        val keep = KeepInTunnel.nets()
        var zone = Cidr.subtract(ruZone, keep)
        var routes = Cidr.complement(zone).size
        var step = 0
        while (routes > maxRoutes && step < gaps.size) {
            zone = Cidr.subtract(Cidr.mergeWithGap(ruZone, gaps[step]), keep)
            routes = Cidr.complement(zone).size
            step++
        }
        return zone to routes
    }

    private fun inTunnel(address: String, zone: List<Ipv4Net>): Boolean {
        val net = Cidr.parse(address) ?: error("«$address» не разобрался")
        return zone.none { net.start >= it.start && net.start <= it.endInclusive }
    }

    @Test
    fun exactListIsTooBigForAndroid() {
        assertTrue(
            "точный список внезапно стал маленьким — проверку можно упростить",
            Cidr.complement(ruZone).size > maxRoutes
        )
    }

    @Test
    fun routesFitTheBudget() {
        val (_, routes) = fittingZone()
        assertTrue("маршрутов $routes — больше, чем система примет", routes <= maxRoutes)
        assertTrue("маршрутов подозрительно мало: $routes", routes > 500)
    }

    @Test
    fun russianServicesStillBypassTunnel() {
        val (zone, _) = fittingZone()
        listOf("5.255.255.242" to "Яндекс",
               "77.88.8.8" to "Яндекс DNS",
               "87.240.190.78" to "ВКонтакте",
               "194.54.14.131" to "Сбер",
               "2.60.0.1" to "МТС",
               "155.212.204.140" to "мессенджер МАКС").forEach { (address, name) ->
            assertFalse("$name ($address) должен идти напрямую", inTunnel(address, zone))
        }
    }

    @Test
    fun blockedServicesStillGoThroughTunnel() {
        val (zone, _) = fittingZone()
        listOf("157.240.229.35" to "Facebook",
               "142.250.185.110" to "Google",
               "104.244.42.1" to "Twitter",
               "185.199.108.153" to "страницы GitHub",
               "192.178.210.100" to "Google AI Studio",
               "194.55.26.46" to "Deutsche Welle").forEach { (address, name) ->
            assertTrue("$name ($address) должен идти через VPN", inTunnel(address, zone))
        }
    }

    @Test
    fun keepListIsSubtracted() {
        val (zone, _) = fittingZone()
        for (net in KeepInTunnel.nets()) {
            assertTrue("${net} обязан остаться в туннеле", inTunnel(net.toString().substringBefore('/'), zone))
        }
    }

    @Test
    fun gapMergeKeepsEverythingCovered() {
        val nets = listOf(Cidr.parse("10.0.0.0/24")!!, Cidr.parse("10.0.2.0/24")!!)
        val merged = Cidr.mergeWithGap(nets, gap = 512)

        assertEquals("должен получиться один кусок", 1, Cidr.merge(merged).size)
        val covered = merged.sumOf { it.size }
        assertTrue("склейка обязана покрывать исходные подсети", covered >= 512)
    }

    @Test
    fun subtractRemovesOnlyWhatAsked() {
        val nets = listOf(Cidr.parse("10.0.0.0/8")!!)
        val trimmed = Cidr.subtract(nets, listOf(Cidr.parse("10.1.0.0/16")!!))

        assertEquals((1L shl 24) - (1L shl 16), trimmed.sumOf { it.size })
        assertTrue(trimmed.none { Cidr.parse("10.1.2.3")!!.start >= it.start && Cidr.parse("10.1.2.3")!!.start <= it.endInclusive })
    }
}
