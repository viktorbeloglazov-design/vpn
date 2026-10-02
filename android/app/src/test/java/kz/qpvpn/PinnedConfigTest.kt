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
    fun throughVpnOnlyTheServiceList() {
        val fresh = AppConfig().pinned()

        assertEquals("через VPN идёт только перечисленное", TunnelMode.INCLUDE, fresh.effectiveMode)
        assertFalse("весь трафик в туннель не загоняем", fresh.fullTunnel)
        assertFalse("прежняя модель «всё, кроме РФ» больше не работает", fresh.mainFilter)
    }

    @Test
    fun oldSettingsMoveToTheNewModel() {
        // Так выглядел файл, записанный версией с моделью «всё, кроме РФ».
        val stored = AppConfig(
            fullTunnel = true,
            mainFilter = true,
            mode = TunnelMode.EXCLUDE,
            appsMode = AppsMode.ONLY_SELECTED,
            selectedApps = listOf("ru.ok.messages"),
            options = AppConfig().options.copy(bypassRuZone = true, blockIpv6 = false),
        )

        val pinned = stored.pinned()

        assertFalse(pinned.fullTunnel)
        assertFalse(pinned.mainFilter)
        assertEquals(TunnelMode.INCLUDE, pinned.effectiveMode)
        assertEquals(AppsMode.OFF, pinned.appsMode)
        assertTrue(pinned.selectedApps.isEmpty())
        assertFalse("российская зона больше не вычитается", pinned.options.bypassRuZone)
        assertTrue("IPv6 всегда в туннеле", pinned.options.blockIpv6)
        assertTrue("DNS из ключа используется всегда", pinned.options.useTunnelDns)
    }

    @Test
    fun theServiceListReachesTheRules() {
        val rules = AppConfig().pinned().rules

        assertTrue(rules.any { it.kind == RuleKind.DOMAIN && it.value == "chatgpt.com" })
        assertTrue(rules.any { it.kind == RuleKind.DOMAIN && it.value == "web.whatsapp.com" })
        assertTrue(rules.any { it.kind == RuleKind.DOMAIN && it.value == "instagram.com" })
        assertTrue(rules.any { it.kind == RuleKind.CIDR && it.value == "91.108.56.0/22" })
    }

    @Test
    fun ownRulesSurvive() {
        // Их человек вписывает сам: обновление зашитого списка не должно
        // их терять.
        val config = AppConfig(
            rules = listOf(RoutingRule(kind = RuleKind.DOMAIN, value = "my-site.example")),
        )

        val pinned = config.pinned()

        assertTrue("добавленное вручную должно остаться",
                   pinned.rules.any { it.value == "my-site.example" })
        assertEquals(1, pinned.ownRules.size)
    }

    @Test
    fun ownRulesDoNotPileUp() {
        // pinned() вызывается при каждом чтении настроек: список не должен
        // расти с каждым разом.
        val config = AppConfig(
            rules = listOf(RoutingRule(kind = RuleKind.DOMAIN, value = "my-site.example")),
        )

        val once = config.pinned()
        val thrice = once.pinned().pinned()

        assertEquals("список не должен расти", once.rules.size, thrice.rules.size)
        assertEquals(1, thrice.ownRules.size)
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
