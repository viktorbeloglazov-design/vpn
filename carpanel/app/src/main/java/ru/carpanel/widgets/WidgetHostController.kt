package ru.carpanel.widgets

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.Context
import android.content.Intent
import android.os.Bundle

/** Свой номер «хозяина виджетов»: по нему система помнит выданные виджеты. */
private const val HOST_ID = 0x4C39

/**
 * Настоящие системные виджеты внутри панели.
 *
 * Android разрешает любой программе быть «хозяином виджетов» — тем же,
 * чем обычно служит домашний экран. Мы просим у системы номер, спрашиваем
 * у хозяина машины согласие на привязку и рисуем чужой виджет в своей клетке.
 */
class WidgetHostController(private val context: Context) {

    private val host = AppWidgetHost(context.applicationContext, HOST_ID)
    private val manager: AppWidgetManager = AppWidgetManager.getInstance(context)

    /** Пока панель на экране, виджеты должны обновляться. */
    fun start() {
        runCatching { host.startListening() }
    }

    fun stop() {
        runCatching { host.stopListening() }
    }

    /** Все виджеты, установленные в машине, по алфавиту. */
    fun providers(): List<AppWidgetProviderInfo> =
        runCatching { manager.installedProviders }
            .getOrDefault(emptyList())
            .filterNotNull()
            .sortedBy { label(it).lowercase() }

    fun label(info: AppWidgetProviderInfo): String =
        runCatching { info.loadLabel(context.packageManager) }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?: info.provider.className.substringAfterLast('.')

    fun allocateId(): Int = runCatching { host.allocateAppWidgetId() }.getOrDefault(0)

    /** Отдать номер системе: вызывается, когда плитку с виджетом убрали. */
    fun release(widgetId: Int) {
        if (widgetId <= 0) return
        runCatching { host.deleteAppWidgetId(widgetId) }
    }

    /** Привязка без вопросов — получается, если согласие уже дано раньше. */
    fun bindQuietly(widgetId: Int, info: AppWidgetProviderInfo): Boolean =
        runCatching { manager.bindAppWidgetIdIfAllowed(widgetId, info.provider) }.getOrDefault(false)

    /** Системный запрос согласия на привязку виджета. */
    fun bindRequestIntent(widgetId: Int, info: AppWidgetProviderInfo): Intent =
        Intent(AppWidgetManager.ACTION_APPWIDGET_BIND).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, info.provider)
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER_PROFILE, info.profile)
        }

    fun info(widgetId: Int): AppWidgetProviderInfo? =
        if (widgetId <= 0) null else runCatching { manager.getAppWidgetInfo(widgetId) }.getOrNull()

    /** Есть ли у виджета собственный экран настройки. */
    fun needsConfigure(info: AppWidgetProviderInfo?): Boolean = info?.configure != null

    /** Открыть экран настройки виджета. Ответ придёт в onActivityResult. */
    fun configure(activity: Activity, widgetId: Int, requestCode: Int): Boolean {
        val info = info(widgetId) ?: return false
        val configure = info.configure ?: return false
        val started = runCatching {
            host.startAppWidgetConfigureActivityForResult(activity, widgetId, 0, requestCode, null)
        }.isSuccess
        if (started) return true

        // Некоторые прошивки не пускают через хозяина виджетов — идём напрямую.
        return runCatching {
            val intent = Intent(AppWidgetManager.ACTION_APPWIDGET_CONFIGURE)
                .setComponent(configure)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            activity.startActivityForResult(intent, requestCode)
            true
        }.getOrDefault(false)
    }

    /** Сам вид виджета, который вставляется в клетку панели. */
    fun createView(widgetId: Int): AppWidgetHostView? {
        val info = info(widgetId) ?: return null
        return runCatching { host.createView(context, widgetId, info) }.getOrNull()
    }

    /** Сообщить виджету, сколько места ему отвели: он подстроит вёрстку. */
    fun resize(view: AppWidgetHostView, widgetId: Int, widthDp: Int, heightDp: Int) {
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, widthDp)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, heightDp)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, widthDp)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, heightDp)
        }
        runCatching { view.updateAppWidgetSize(options, widthDp, heightDp, widthDp, heightDp) }
        runCatching { manager.updateAppWidgetOptions(widgetId, options) }
    }
}
