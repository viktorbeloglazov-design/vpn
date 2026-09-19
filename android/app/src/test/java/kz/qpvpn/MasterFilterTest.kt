package kz.qpvpn

import kz.qpvpn.model.AppConfig
import kz.qpvpn.model.MasterFilter
import kz.qpvpn.model.RuleKind
import kz.qpvpn.model.TunnelMode
import kz.qpvpn.net.Cidr
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Главный фильтр — единственный переключатель, которым пользуются каждый день. */
class MasterFilterTest {

    @Test
    fun everyDomainIsValid() {
        for (domain in MasterFilter.domains) {
            assertNull("«$domain» не похож на домен", Cidr.ruleError(RuleKind.DOMAIN, domain))
        }
    }

    @Test
    fun hasNoDuplicates() {
        val all = MasterFilter.sections.flatMap { it.domains }
        assertEquals("в списке есть повторы", all.size, all.distinct().size)
    }

    @Test
    fun coversEverythingThatNeedsVpn() {
        val domains = MasterFilter.domains
        listOf(
            "openai.com", "claude.ai", "gemini.google.com",      // нейросети
            "instagram.com", "facebook.com", "x.com",            // соцсети
            "discord.com", "whatsapp.com", "signal.org",         // мессенджеры
            "youtube.com", "netflix.com", "spotify.com",         // видео и музыка
            "canva.com", "figma.com", "notion.so",               // работа
            "github.com", "docker.com",                          // разработка
            "amazon.com", "paypal.com",                          // покупки
        ).forEach { assertTrue("не хватает $it", it in domains) }

        assertTrue("список подозрительно мал: ${domains.size}", domains.size >= 200)
    }

    @Test
    fun leavesRussianServicesAlone() {
        // В туннель не должно попадать ничего российского: это и есть смысл фильтра.
        val suspicious = MasterFilter.domains.filter {
            it.endsWith(".ru") || it.endsWith(".рф") || it.endsWith(".su")
        }
        assertTrue("в списке оказались российские домены: $suspicious", suspicious.isEmpty())
    }

    @Test
    fun mainFilterOverridesModeAndIsOnByDefault() {
        val fresh = AppConfig()
        assertTrue("главный фильтр должен быть включён сразу", fresh.mainFilter)
        assertEquals(TunnelMode.INCLUDE, fresh.effectiveMode)

        val manual = fresh.copy(mainFilter = false, mode = TunnelMode.EXCLUDE)
        assertEquals(TunnelMode.EXCLUDE, manual.effectiveMode)
    }
}
