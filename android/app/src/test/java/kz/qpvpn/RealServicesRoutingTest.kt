package kz.qpvpn

import kz.qpvpn.model.RuleKind
import kz.qpvpn.model.VpnServices
import kz.qpvpn.net.Cidr
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Живая проверка маршрутизации на настоящих адресах.
 *
 * Модель простая: через VPN идёт только список сервисов — мессенджеры,
 * видео, ИИ. Всё остальное идёт напрямую: российские сайты, банки,
 * маркетплейсы, госуслуги и вообще весь прочий интернет.
 *
 * Те же адреса проверяются в версии для Mac — списки обязаны совпадать
 * один в один. Иначе на телефоне сервис работает, а на компьютере нет,
 * и разобраться в этом невозможно.
 */
class RealServicesRoutingTest {

    private val tunnelNets = VpnServices.services
        .flatMap { it.networks }
        .mapNotNull { Cidr.parse(it) }

    private fun goesThroughVpn(address: String): Boolean {
        val net = Cidr.parse(address) ?: return false
        return tunnelNets.any { net.start >= it.start && net.start <= it.endInclusive }
    }

    @Test
    fun servicesFromTheListGoThroughVpn() {
        val services = listOf(
            "WhatsApp" to listOf("157.240.1.1", "31.13.64.35", "179.60.192.1"),
            "Instagram" to listOf("157.240.253.174", "31.13.24.1"),
            "Instagram, картинки" to listOf("57.144.1.1"),
            "Telegram" to listOf("149.154.167.51", "91.108.56.130", "91.108.4.1"),
            "YouTube" to listOf("142.250.74.14", "172.217.16.78", "216.58.192.1"),
            "YouTube, видео" to listOf("173.194.1.1", "74.125.1.1"),
            "Gemini" to listOf("142.251.1.1", "209.85.128.1"),
            "Claude" to listOf("160.79.104.10", "160.79.105.200"),
        )

        for ((name, addresses) in services) {
            for (address in addresses) {
                assertTrue(
                    "$name ($address) должен идти через VPN — иначе сервис останется заблокированным",
                    goesThroughVpn(address),
                )
            }
        }
    }

    @Test
    fun russianServicesGoDirect() {
        val russian = listOf(
            "МАХ" to listOf("155.212.204.5", "155.212.204.143"),
            "Госуслуги" to listOf("213.59.253.7", "212.42.65.4"),
            "Налоговая" to listOf("195.208.66.236"),
            "Сбербанк" to listOf("84.252.149.206"),
            "Т-Банк" to listOf("178.130.128.27"),
            "Альфа-Банк" to listOf("217.12.104.100"),
            "ВТБ" to listOf("195.242.82.13"),
            "ВКонтакте" to listOf("87.240.129.133"),
            "Почта Mail.ru" to listOf("185.180.201.1"),
            "Яндекс" to listOf("5.255.255.77", "77.88.44.55"),
            "Озон" to listOf("185.73.193.68"),
            "Wildberries" to listOf("185.62.202.2"),
            "Авито" to listOf("176.114.120.24"),
            "РЖД" to listOf("212.164.138.120"),
            "Ростелеком" to listOf("87.226.162.216"),
        )

        for ((name, addresses) in russian) {
            for (address in addresses) {
                assertFalse(
                    "$name ($address) должен идти напрямую — через VPN он может не пустить",
                    goesThroughVpn(address),
                )
            }
        }
    }

    @Test
    fun cloudflareNetworksDoNotEnterTheTunnel() {
        // Доказано на живом примере: за Cloudflare стоят и российские
        // сайты. Если завернуть сети Cloudflare в туннель, они поедут
        // через Казахстан вместо прямого пути.
        for (address in listOf("104.18.32.115", "172.64.155.141",
                               "104.21.32.39", "172.67.182.196")) {
            assertFalse(
                "Сеть Cloudflare ($address) не должна уходить в туннель по адресу",
                goesThroughVpn(address),
            )
        }
    }

    @Test
    fun theRestOfTheInternetGoesDirect() {
        val others = listOf(
            "LinkedIn" to "13.107.42.14",
            "Spotify" to "35.186.224.25",
            "GitHub Pages" to "185.199.108.153",
            "Fastly" to "151.101.1.140",
            "Amazon" to "52.95.110.1",
        )

        for ((name, address) in others) {
            assertFalse(
                "$name ($address) в списке не числится — должен идти напрямую",
                goesThroughVpn(address),
            )
        }
    }

    @Test
    fun servicesOnCloudflareEnterByName() {
        // У ChatGPT и прочих ИИ своих сетей нет: адрес узнаётся у DNS
        // и прокладывается поштучно. Поэтому в списке обязаны быть имена.
        val rules = VpnServices.rules()

        for (name in listOf("chatgpt.com", "api.openai.com", "perplexity.ai",
                            "grok.com", "chat.deepseek.com")) {
            assertTrue(
                "Без имени $name сервис через VPN не пойдёт",
                rules.any { it.kind == RuleKind.DOMAIN && it.value == name },
            )
        }
    }

    @Test
    fun theListMatchesTheMacVersion() {
        // Сверка с Mac: если один список правят, а другой нет, сервис
        // работает на одном устройстве и не работает на другом.
        val expected = listOf(
            "WhatsApp", "Instagram", "Telegram", "YouTube",
            "ChatGPT", "Claude", "Gemini", "Perplexity", "Grok", "Copilot",
            "DeepSeek", "Mistral", "Midjourney", "Suno", "Hugging Face",
        )
        assertTrue(
            "список расходится с версией для Mac: ${VpnServices.titles}",
            VpnServices.titles == expected,
        )
    }
}
