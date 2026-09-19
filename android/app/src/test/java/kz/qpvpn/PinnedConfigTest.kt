package kz.qpvpn

import kz.qpvpn.model.AppConfig
import kz.qpvpn.model.AppsMode
import kz.qpvpn.model.RoutingRule
import kz.qpvpn.model.RuleKind
import kz.qpvpn.model.TunnelMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Маршрутизация зашита: переключателей для неё в программе больше нет,
 * поэтому настройки обязаны приводиться к одному и тому же виду — иначе
 * значение, сохранённое прежней версией, останется навсегда.
 */
class PinnedConfigTest {

    @Test
    fun freshConfigIsAlreadyPinned() {
        val fresh = AppConfig()
        assertEquals("заводские настройки не должны ничего менять", fresh, fresh.pinned())
        assertTrue("обход блокировок работает всегда", fresh.mainFilter)
        assertFalse("весь трафик в туннель не загоняем", fresh.fullTunnel)
        assertEquals(TunnelMode.EXCLUDE, fresh.effectiveMode)
    }

    @Test
    fun oldSettingsAreBroughtBack() {
        // Так мог выглядеть файл, сохранённый версией с переключателями.
        val stored = AppConfig(
            fullTunnel = true,
            mainFilter = false,
            mode = TunnelMode.INCLUDE,
            rules = listOf(RoutingRule(kind = RuleKind.DOMAIN, value = "example.com")),
            appsMode = AppsMode.ONLY_SELECTED,
            selectedApps = listOf("ru.ok.messages"),
            options = AppConfig().options.copy(bypassRuZone = false, blockIpv6 = false),
        )

        val pinned = stored.pinned()

        assertFalse(pinned.fullTunnel)
        assertTrue(pinned.mainFilter)
        assertEquals(TunnelMode.EXCLUDE, pinned.mode)
        assertEquals(TunnelMode.EXCLUDE, pinned.effectiveMode)
        assertTrue("свои правила больше не задаются", pinned.rules.isEmpty())
        assertEquals(AppsMode.OFF, pinned.appsMode)
        assertTrue(pinned.selectedApps.isEmpty())
        assertTrue("российская зона всегда мимо туннеля", pinned.options.bypassRuZone)
        assertTrue("IPv6 всегда в туннеле", pinned.options.blockIpv6)
        assertTrue("DNS из ключа используется всегда", pinned.options.useTunnelDns)
    }

    @Test
    fun theOnlySwitchSurvives() {
        // Рабочие ресурсы — единственное, что человек выбирает сам.
        assertFalse(AppConfig().copy(workFilter = false).pinned().workFilter)
        assertTrue(AppConfig().copy(workFilter = true).pinned().workFilter)
    }

    @Test
    fun mtuStaysAsChosen() {
        // MTU к маршрутизации не относится: его иногда приходится менять руками.
        assertEquals(1280, AppConfig().let { it.copy(options = it.options.copy(mtu = 1280)) }.pinned().options.mtu)
    }
}
