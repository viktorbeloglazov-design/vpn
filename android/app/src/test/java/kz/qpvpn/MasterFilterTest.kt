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
    fun everyPackageLooksLikeAndroidPackage() {
        val shape = Regex("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z0-9_]+)+$")
        for (name in MasterFilter.packages) {
            assertTrue("«$name» не похоже на имя пакета", shape.matches(name))
        }
    }

    @Test
    fun packagesHaveNoDuplicates() {
        val all = MasterFilter.appSections.flatMap { it.packages }
        assertEquals("в списке программ есть повторы", all.size, all.distinct().size)
    }

    @Test
    fun packagesCoverWhatPeopleActuallyHave() {
        val packages = MasterFilter.packages
        listOf(
            "com.openai.chatgpt",                      // нейросети
            "com.instagram.android", "com.facebook.katana",
            "com.whatsapp", "com.discord",             // мессенджеры
            "com.google.android.youtube", "com.netflix.mediaclient", "com.spotify.music",
            "com.canva.editor", "com.figma.mirror",    // работа
            "com.android.chrome", "com.sec.android.app.sbrowser", // браузеры Samsung
            "com.amazon.mShop.android.shopping", "com.paypal.android.p2pmobile",
            "com.booking", "com.airbnb.android",
            "com.valvesoftware.android.steam.community",
        ).forEach { assertTrue("не хватает $it", it in packages) }

        assertTrue("список программ мал: ${packages.size}", packages.size >= 80)
    }

    @Test
    fun mainFilterOverridesModeAndIsOnByDefault() {
        val fresh = AppConfig()
        assertTrue("главный фильтр должен быть включён сразу", fresh.mainFilter)

        // Главный фильтр — это «всё через VPN, кроме российских адресов»:
        // так заблокированные сервисы открываются, даже если их адрес
        // приложение заранее не знает.
        assertEquals(TunnelMode.EXCLUDE, fresh.effectiveMode)

        val manual = fresh.copy(mainFilter = false, mode = TunnelMode.INCLUDE)
        assertEquals(TunnelMode.INCLUDE, manual.effectiveMode)
    }

    @Test
    fun fullTunnelWinsOverEverything() {
        val fresh = AppConfig()
        assertTrue("весь трафик по умолчанию выключен", !fresh.fullTunnel)

        val all = fresh.copy(fullTunnel = true)
        assertEquals(TunnelMode.FULL, all.effectiveMode)

        val alsoWithManualMode = fresh.copy(fullTunnel = true, mainFilter = false, mode = TunnelMode.INCLUDE)
        assertEquals(TunnelMode.FULL, alsoWithManualMode.effectiveMode)
    }
}
