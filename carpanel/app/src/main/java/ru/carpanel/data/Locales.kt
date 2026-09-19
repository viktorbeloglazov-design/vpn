package ru.carpanel.data

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * Русский язык интерфейса независимо от языка машины.
 *
 * Прошивка Lixiang нередко приезжает с китайской или английской системой,
 * и тогда Android показывает программе чужие системные строки. Мы
 * подменяем язык только для себя: настройки самой машины не трогаются.
 */
object Locales {

    val russian: Locale = Locale.forLanguageTag("ru-RU")

    /** Обернуть окружение программы русской локалью, если хозяин так решил. */
    fun wrap(base: Context): Context {
        val forced = runCatching { Store(base).settings.forceRussian }.getOrDefault(true)
        if (!forced) return base
        return force(base)
    }

    private fun force(base: Context): Context {
        Locale.setDefault(russian)
        val configuration = Configuration(base.resources.configuration)
        configuration.setLocale(russian)
        configuration.setLayoutDirection(russian)
        return runCatching { base.createConfigurationContext(configuration) }.getOrDefault(base)
    }
}
