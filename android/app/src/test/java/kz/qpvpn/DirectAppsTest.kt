package kz.qpvpn

import kz.qpvpn.model.DirectApps
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Железное правило: МАХ обязан идти мимо VPN в любом виде.
 *
 * Маршруты тут ни при чём — его адреса и так прямые. МАХ сам проверяет,
 * поднят ли на телефоне туннель, и показывает «Отключите VPN». Помогает
 * только одно: система не должна показывать ему туннель вовсе.
 */
class DirectAppsTest {

    @Test
    fun maxIsInTheListByItsRealPackage() {
        // Имя из магазина: play.google.com/store/apps/details?id=ru.oneme.app
        assertTrue("МАХ пропал из списка", "ru.oneme.app" in DirectApps.packages)
        assertTrue(DirectApps.matches("ru.oneme.app", "MAX"))
    }

    @Test
    fun maxIsCaughtEvenIfRebuiltUnderAnotherName() {
        // Бета, региональная сборка, предустановленная версия — имя может
        // отличаться, но кусок «oneme» остаётся.
        for (name in listOf(
            "ru.oneme.app.beta",
            "ru.oneme.app.rustore",
            "com.vk.oneme",
            "ru.max.messenger",
            "com.maxmessenger.android",
        )) {
            assertTrue("$name должен опознаться как МАХ", DirectApps.matches(name, ""))
        }
    }

    @Test
    fun maxIsCaughtByItsNameOnScreen() {
        // Если переименуют пакет целиком, останется название на экране.
        for (label in listOf("MAX", "max", "МАХ", "мах", "  Max  ", "MAX мессенджер")) {
            assertTrue(
                "«$label» должно опознаться как МАХ",
                DirectApps.matches("com.example.unknown", label),
            )
        }
    }

    @Test
    fun ordinaryAppsAreNotTouched() {
        // Правило не должно хватать лишнего: иначе обычные программы
        // молча останутся без VPN, и человек не поймёт почему.
        for ((name, label) in listOf(
            "com.instagram.android" to "Instagram",
            "com.google.android.youtube" to "YouTube",
            "com.rockstargames.gtasa" to "Max Payne Mobile",
            "org.telegram.messenger" to "Telegram",
            "com.openai.chatgpt" to "ChatGPT",
            "com.anthropic.claude" to "Claude",
            "com.facebook.katana" to "Facebook",
            "com.twitter.android" to "X",
            "com.linkedin.android" to "LinkedIn",
            "com.spotify.music" to "Spotify",
            "com.discord" to "Discord",
            "com.netflix.mediaclient" to "Netflix",
            "com.microsoft.teams" to "Teams",
            "kz.qpvpn" to "QP VPN",
        )) {
            assertFalse("$name ($label) не должен уходить мимо VPN", DirectApps.matches(name, label))
        }
    }

    @Test
    fun russianAppsAreRecognisedWithoutBeingListed() {
        // Перечислять их поимённо бессмысленно: список никогда не будет
        // полным, а каждая пропущенная программа — очередное «Отключите VPN».
        // Российской программе туннель не нужен: её адреса и так прямые.
        for ((name, label) in listOf(
            "ru.vtb24.mobilebanking.android" to "ВТБ Онлайн",
            "com.idamob.tinkoff.android" to "Т-Банк",
            "com.wildberries.ru" to "Wildberries",
            "com.avito.android" to "Авито",
            "ru.ozon.app.android" to "Ozon",
            "ru.yandex.searchplugin" to "Яндекс",
            "com.vkontakte.android" to "ВКонтакте",
            "ru.kinopoisk" to "Кинопоиск",
            "ru.dublgis.dgismobile" to "2ГИС",
            "ru.rzd.pass" to "РЖД Пассажирам",
            "ru.sberbankmobile.oplata" to "СберБанк",
        )) {
            assertTrue("$name ($label) должен идти мимо VPN", DirectApps.matches(name, label))
        }
    }

    @Test
    fun russianAppsThatRefuseVpnAreListed() {
        // Те же грабли, что у МАХ: программа сама смотрит, включён ли VPN.
        for (name in listOf(
            "ru.rostel",                       // Госуслуги
            "ru.gosuslugi.goskey",             // Госключ
            "ru.sberbankmobile",               // СберБанк Онлайн
            "com.idamob.tinkoff.android",      // Т-Банк
            "ru.vtb24.mobilebanking.android",  // ВТБ
            "ru.alfabank.mobile.android",      // Альфа-Банк
            "ru.nspk.mirpay",                  // Mir Pay
        )) {
            assertTrue("$name должен идти мимо VPN", name in DirectApps.packages)
        }
    }

    @Test
    fun listIsCleanAndLowercase() {
        assertEquals("в списке есть повторы", DirectApps.packages.distinct().size, DirectApps.packages.size)
        assertEquals(
            "имена пакетов не должны совпадать без учёта регистра — это те же повторы",
            DirectApps.packages.map { it.lowercase() }.distinct().size,
            DirectApps.packages.size,
        )
        assertTrue(
            "названия для сравнения тоже должны быть строчными",
            DirectApps.labels.all { it == it.lowercase() },
        )
        assertTrue(
            "куски имени тоже",
            DirectApps.fragments.all { it == it.lowercase() },
        )
        assertTrue(
            "начала имён тоже",
            DirectApps.prefixes.all { it == it.lowercase() },
        )
        assertTrue(
            "окончания имён тоже",
            DirectApps.suffixes.all { it == it.lowercase() },
        )
        assertFalse("нельзя выключать VPN для самого себя", "kz.qpvpn" in DirectApps.packages)
    }

    @Test
    fun manifestLetsAndroidSeeThoseApps() {
        // На Android 11+ система врёт, что программа не установлена, если
        // её имя не объявлено в манифесте. Без этого МАХ в список не попадёт.
        val manifest = java.io.File("src/main/AndroidManifest.xml").readText()
        for (name in DirectApps.packages) {
            assertTrue(
                "в манифесте нет <package android:name=\"$name\" /> — система не увидит программу",
                manifest.contains("<package android:name=\"$name\" />"),
            )
        }
    }
}
