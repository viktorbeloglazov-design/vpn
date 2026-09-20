package kz.qpvpn

import kz.qpvpn.model.KeepInTunnel
import kz.qpvpn.net.Cidr
import kz.qpvpn.net.Ipv4Net
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Живая проверка зашитой маршрутизации на настоящих адресах.
 *
 * Переключателей больше нет, поэтому поведение обязано быть одним и тем же
 * у всех: российские сервисы — напрямую, заблокированные — через VPN. Адреса
 * записаны числами, а не именами: в сборке нет ни интернета, ни DNS, а имя
 * всё равно разрешилось бы в адрес ближайшей сети, а не абонентской.
 */
class RealServicesRoutingTest {

    private val maxRoutes = 4_000
    private val gaps = listOf(4_096L, 16_384L, 65_536L, 262_144L, 1_048_576L)

    /** Подсети, которые остаются вне туннеля, — ровно как считает программа. */
    private val directZone: List<Ipv4Net> by lazy {
        val exact = File("src/main/res/raw/ru_ipv4.txt").readLines()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .mapNotNull { Cidr.parse(it) }

        val keep = KeepInTunnel.nets()
        var zone = Cidr.subtract(exact, keep)
        var routes = Cidr.complement(zone).size
        var step = 0
        while (routes > maxRoutes && step < gaps.size) {
            zone = Cidr.subtract(Cidr.mergeWithGap(exact, gaps[step]), keep)
            routes = Cidr.complement(zone).size
            step++
        }
        zone
    }

    private fun goesDirect(address: String): Boolean {
        val net = Cidr.parse(address) ?: error("«$address» не разобрался")
        return directZone.any { net.start >= it.start && net.start <= it.endInclusive }
    }

    @Test
    fun russianServicesGoDirect() {
        val russian = mapOf(
            "МАХ" to listOf(
                "155.212.204.5", "155.212.204.74", "155.212.204.78",
                "155.212.204.140", "155.212.204.143", "155.212.204.193",
            ),
            "Госуслуги" to listOf("213.59.253.7", "213.59.254.7"),
            "Налоговая" to listOf("195.208.66.236"),
            "Мос.ру" to listOf("212.11.155.134"),
            "Сбербанк" to listOf("84.252.149.206"),
            "Т-Банк" to listOf("178.130.128.27"),
            "Альфа-Банк" to listOf("217.12.104.100"),
            "ВТБ" to listOf("195.242.82.13", "195.242.83.13"),
            "ВКонтакте" to listOf("87.240.129.133", "87.240.132.67", "93.186.225.194"),
            "Почта Mail.ru" to listOf("185.180.201.1", "89.221.239.1", "90.156.232.4"),
            "Яндекс" to listOf("5.255.255.77", "77.88.44.55", "77.88.55.88"),
            "Озон" to listOf("185.73.193.68", "185.73.194.82"),
            "Wildberries" to listOf("185.62.202.2"),
            "Авито" to listOf("176.114.120.24", "176.114.124.24"),
            "2ГИС" to listOf("91.236.49.6"),
            "РЖД" to listOf("212.164.138.120", "212.164.138.131"),
            "Почта России" to listOf("212.164.140.129", "212.164.140.153"),
            "Аэрофлот" to listOf("195.209.66.33"),
            "Ростелеком" to listOf("87.226.162.216"),
        )

        russian.forEach { (name, addresses) ->
            addresses.forEach { address ->
                assertTrue(
                    "$name ($address) должен идти напрямую, иначе он не пустит из Казахстана",
                    goesDirect("$address/32"),
                )
            }
        }
    }

    @Test
    fun blockedServicesGoThroughTunnel() {
        val blocked = mapOf(
            "Instagram" to listOf("157.240.253.174"),
            "Facebook" to listOf("157.240.253.35"),
            "X (Twitter)" to listOf("104.244.42.129", "104.244.42.65"),
            "YouTube" to listOf("142.250.74.14", "172.217.16.78"),
            "ChatGPT" to listOf("104.18.32.115", "172.64.155.141"),
            "Claude" to listOf("160.79.104.10"),
            "Google AI Studio" to listOf("142.250.74.14"),
            "Discord" to listOf("162.159.128.233", "162.159.136.232"),
            "LinkedIn" to listOf("13.107.42.14"),
            "Spotify" to listOf("35.186.224.25"),
            "GitHub" to listOf("140.82.121.4"),
            "GitHub Pages" to listOf("185.199.108.153"),
            "Fastly (CDN многих сервисов)" to listOf("151.101.1.140", "146.75.2.10", "199.232.5.100"),
        )

        blocked.forEach { (name, addresses) ->
            addresses.forEach { address ->
                assertTrue(
                    "$name ($address) обязан уходить в туннель, иначе сервис останется заблокированным",
                    !goesDirect("$address/32"),
                )
            }
        }
    }
}
