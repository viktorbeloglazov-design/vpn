package kz.qpvpn

import kz.qpvpn.model.RuleKind
import kz.qpvpn.net.Cidr
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CidrTest {

    @Test
    fun parsesAddressesAndNetworks() {
        assertEquals("10.0.0.0/8", Cidr.parse("10.0.0.0/8").toString())
        assertEquals("5.35.96.12/32", Cidr.parse("5.35.96.12").toString())
        assertEquals("192.168.1.0/24", Cidr.parse("192.168.1.77/24").toString())
        assertNull(Cidr.parse("10.0.0.0/33"))
        assertNull(Cidr.parse("999.1.1.1"))
        assertNull(Cidr.parse("kaspi.kz"))
    }

    @Test
    fun recognisesDomains() {
        assertTrue(Cidr.isDomain("kaspi.kz"))
        assertTrue(Cidr.isDomain("seller.wildberries.ru"))
        assertTrue(!Cidr.isDomain("kaspi"))
        assertTrue(!Cidr.isDomain("-kaspi.kz"))
        assertTrue(!Cidr.isDomain("kaspi..kz"))
    }

    @Test
    fun ruleErrorsMatchTheInput() {
        assertNull(Cidr.ruleError(RuleKind.DOMAIN, "kaspi.kz"))
        assertNotNull(Cidr.ruleError(RuleKind.DOMAIN, "10.0.0.0/8"))
        assertNull(Cidr.ruleError(RuleKind.CIDR, "10.0.0.0/8"))
        assertNotNull(Cidr.ruleError(RuleKind.CIDR, "kaspi.kz"))
        assertNotNull(Cidr.ruleError(RuleKind.CIDR, "   "))
    }

    @Test
    fun complementOfNothingIsEverything() {
        assertEquals(listOf("0.0.0.0/0"), Cidr.complement(emptyList()).map { it.toString() })
    }

    /** Главная проверка: «всё кроме» считается как дополнение и ничего не теряет. */
    @Test
    fun complementCoversEverythingExceptExcluded() {
        val excluded = listOf("10.0.0.0/8", "192.168.0.0/16").map { Cidr.parse(it)!! }
        val result = Cidr.complement(excluded)

        val total = result.sumOf { it.size }
        val expected = (1L shl 32) - excluded.sumOf { it.size }
        assertEquals(expected, total)

        // Исключённые адреса в дополнение попасть не должны.
        val excludedAddress = Cidr.parseAddress("10.1.2.3")!!
        assertTrue(result.none { excludedAddress >= it.start && excludedAddress <= it.endInclusive })

        // А соседний адрес — должен.
        val keptAddress = Cidr.parseAddress("11.1.2.3")!!
        assertTrue(result.any { keptAddress >= it.start && keptAddress <= it.endInclusive })
    }

    @Test
    fun complementHandlesOverlappingAndTouchingRanges() {
        val excluded = listOf("10.0.0.0/8", "10.1.0.0/16", "11.0.0.0/8").map { Cidr.parse(it)!! }
        val result = Cidr.complement(excluded)

        val total = result.sumOf { it.size }
        // 10.0.0.0/8 и 11.0.0.0/8 — это 2 * 2^24 адресов, вложенная /16 не считается дважды.
        assertEquals((1L shl 32) - 2 * (1L shl 24), total)
    }

    @Test
    fun mergeCollapsesNeighbours() {
        val nets = listOf("10.0.0.0/9", "10.128.0.0/9").map { Cidr.parse(it)!! }
        assertEquals(listOf("10.0.0.0/8"), Cidr.merge(nets).map { it.toString() })
    }

    @Test
    fun rangeToNetsIsMinimal() {
        val nets = Cidr.rangeToNets(Cidr.parseAddress("192.168.1.0")!!, Cidr.parseAddress("192.168.1.255")!!)
        assertEquals(listOf("192.168.1.0/24"), nets.map { it.toString() })
    }
}
