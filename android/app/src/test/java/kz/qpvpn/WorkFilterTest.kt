package kz.qpvpn

import kz.qpvpn.model.AppConfig
import kz.qpvpn.model.WorkFilter
import kz.qpvpn.net.Cidr
import kz.qpvpn.net.Ipv4Net
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Второй переключатель: рабочие ресурсы.
 *
 * Их адрес выдан России, поэтому важно проверить главное: когда переключатель
 * включён, туннель забирает эти адреса даже при включённом обходе российской
 * зоны, а когда выключен — они остаются напрямую.
 */
class WorkFilterTest {

    private fun workNets(): List<Ipv4Net> = WorkFilter.hosts.mapNotNull { Cidr.parse(it) }

    /** Подсеть России, внутри которой лежит рабочий адрес. */
    private val ruZone = listOf(Cidr.parse("135.106.136.0/21")!!)

    private fun inside(nets: List<Ipv4Net>, net: Ipv4Net): Boolean =
        nets.any { net.start >= it.start && net.endInclusive <= it.endInclusive }

    @Test
    fun everyResourceGivesUsableHost() {
        assertTrue("список рабочих ресурсов пуст", WorkFilter.resources.isNotEmpty())
        for (resource in WorkFilter.resources) {
            val host = resource.host
            assertTrue(
                "«$host» не похож ни на адрес, ни на домен",
                Cidr.parse(host) != null || Cidr.isDomain(host),
            )
            assertFalse("в узле осталась схема или путь: $host", host.contains('/'))
        }
    }

    @Test
    fun hostsAreCountedOnce() {
        assertEquals(WorkFilter.hosts.size, WorkFilter.hosts.distinct().size)
        assertTrue("ссылки ведут на один узел", WorkFilter.hosts.size <= WorkFilter.resources.size)
    }

    @Test
    fun onByDefault() {
        assertTrue("рабочие ресурсы должны идти через VPN сразу", AppConfig().workFilter)
    }

    @Test
    fun switchedOnItBeatsRuZone() {
        val work = workNets()
        assertTrue("рабочие адреса не разобрались", work.isNotEmpty())

        // Так считает туннель: всё, кроме российской зоны, плюс рабочие адреса.
        val routed = Cidr.merge(Cidr.complement(ruZone) + work)

        for (net in work) {
            assertTrue("$net должен уходить в туннель", inside(routed, net))
        }
    }

    @Test
    fun switchedOffItStaysDirect() {
        val work = workNets()
        val routed = Cidr.complement(ruZone + work)

        for (net in work) {
            assertFalse("$net не должен попадать в туннель", inside(routed, net))
        }
    }

    @Test
    fun switchedOffItLeavesFullTunnel() {
        val work = workNets()
        val routed = Cidr.complement(work)

        assertEquals(
            "вместе должны покрывать всё адресное пространство",
            1L shl 32,
            routed.sumOf { it.size } + Cidr.merge(work).sumOf { it.size },
        )
        for (net in work) {
            assertFalse("$net должен остаться вне туннеля", inside(routed, net))
        }
    }
}
