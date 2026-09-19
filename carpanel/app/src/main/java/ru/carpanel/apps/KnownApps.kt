package ru.carpanel.apps

/**
 * Программы, которые чаще всего ставят на экран машины.
 *
 * Список нужен для двух вещей: подсказать их первыми при добавлении плитки
 * и знать запасную ссылку запуска — иногда программа не отдаёт системе
 * обычный значок, но открывается по своей ссылке.
 */
object KnownApps {

    data class Entry(val packageName: String, val label: String, val uri: String? = null)

    val list = listOf(
        Entry("ru.yandex.yandexnavi", "Яндекс Навигатор", "yandexnavi://"),
        Entry("ru.yandex.yandexmaps", "Яндекс Карты", "yandexmaps://"),
        Entry("ru.yandex.music", "Яндекс Музыка", "yandexmusic://"),
        Entry("ru.yandex.searchplugin", "Яндекс"),
        Entry("ru.dublgis.dgismobile", "2ГИС", "dgis://"),
        Entry("com.yandex.browser", "Яндекс Браузер"),
        Entry("org.telegram.messenger", "Telegram"),
        Entry("com.spotify.music", "Spotify", "spotify://"),
        Entry("com.google.android.youtube", "YouTube"),
        Entry("ru.rutube.app", "Rutube"),
        Entry("com.vkontakte.android", "ВКонтакте"),
        Entry("ru.vk.store", "RuStore"),
    )

    private val byPackage = list.associateBy { it.packageName }

    /** Человеческое название для известного пакета. */
    fun label(packageName: String?): String? = byPackage[packageName]?.label

    /** Запасная ссылка запуска, если обычного значка у программы нет. */
    fun fallbackUri(packageName: String?): String? = byPackage[packageName]?.uri

    fun isKnown(packageName: String?): Boolean = byPackage.containsKey(packageName)
}
