package kz.qpvpn

import kz.qpvpn.net.Cidr
import kz.qpvpn.net.Ipv4Net
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random
import kotlin.system.measureTimeMillis

/**
 * Проверки режима «вся российская зона мимо VPN».
 *
 * Список России — тысячи подсетей, и весь интернет за их вычетом считается
 * на телефоне при каждом подключении. Здесь проверяется, что счёт сходится
 * без потерь и укладывается в разумное время.
 */
class RuZoneRoutingTest {

    /** Набор, сопоставимый по размеру с реальным адресным пространством России. */
    private fun largeSet(count: Int = 8_649): List<Ipv4Net> {
        val random = Random(42)
        val nets = HashSet<Ipv4Net>(count * 2)
        while (nets.size < count) {
            val start = (random.nextLong(0, 0xFFFFFFFFL) / 256) * 256
            nets += Ipv4Net(start, 24)
        }
        return nets.toList()
    }

    @Test
    fun complementCoversExactlyTheRest() {
        val excluded = largeSet()
        val routed = Cidr.complement(excluded)

        val bypassAddresses = Cidr.merge(excluded).sumOf { it.size }
        val tunnelAddresses = routed.sumOf { it.size }

        assertEquals(
            "вместе должны покрывать всё адресное пространство",
            1L shl 32,
            bypassAddresses + tunnelAddresses,
        )
    }

    @Test
    fun excludedNetworksNeverEnterTheTunnel() {
        val excluded = largeSet(2_000)
        val routed = Cidr.complement(excluded)

        for (net in excluded.take(200)) {
            val insideTunnel = routed.any { net.start >= it.start && net.start <= it.endInclusive }
            assertTrue("подсеть $net не должна попадать в туннель", !insideTunnel)
        }
    }

    @Test
    fun complementIsFastEnoughForPhone() {
        val excluded = largeSet()
        var routes = 0
        val millis = measureTimeMillis { routes = Cidr.complement(excluded).size }

        assertTrue("маршрутов должно получиться много, вышло $routes", routes > 1_000)
        assertTrue("расчёт занял $millis мс — для телефона слишком долго", millis < 3_000)
    }

    @Test
    fun userRulesAndRuZoneCombine() {
        val ruZone = listOf(Cidr.parse("5.8.0.0/16")!!, Cidr.parse("31.13.0.0/16")!!)
        val userRules = listOf(Cidr.parse("95.213.0.0/16")!!)

        val routed = Cidr.complement(ruZone + userRules)
        val tunnelAddresses = routed.sumOf { it.size }
        val bypassAddresses = (ruZone + userRules).sumOf { it.size }

        assertEquals(1L shl 32, tunnelAddresses + bypassAddresses)
    }
}
