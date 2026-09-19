package ru.carpanel.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import androidx.core.graphics.drawable.toBitmap
import ru.carpanel.MainActivity
import ru.carpanel.R
import ru.carpanel.apps.AppCatalog
import ru.carpanel.data.Store
import ru.carpanel.model.AppSet

/**
 * Набор программ на домашнем экране машины.
 *
 * Это настоящий системный виджет: его кладут на штатный рабочий стол
 * прошивки так же, как часы или погоду. Содержимое — тот же набор, что
 * включается переключателем в панели.
 */
class AppSetWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        val views = build(context)
        appWidgetIds.forEach { id -> runCatching { manager.updateAppWidget(id, views) } }
    }

    companion object {

        private val slots = intArrayOf(
            R.id.slot_0, R.id.slot_1, R.id.slot_2, R.id.slot_3, R.id.slot_4, R.id.slot_5,
        )
        private val icons = intArrayOf(
            R.id.icon_0, R.id.icon_1, R.id.icon_2, R.id.icon_3, R.id.icon_4, R.id.icon_5,
        )
        private val labels = intArrayOf(
            R.id.label_0, R.id.label_1, R.id.label_2, R.id.label_3, R.id.label_4, R.id.label_5,
        )

        /** Перерисовать все выложенные виджеты — после правки набора. */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = runCatching {
                manager.getAppWidgetIds(ComponentName(context, AppSetWidget::class.java))
            }.getOrNull() ?: return
            if (ids.isEmpty()) return

            val views = build(context)
            ids.forEach { id -> runCatching { manager.updateAppWidget(id, views) } }
        }

        private fun build(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_app_set)
            val config = Store(context).config.value
            val catalog = AppCatalog(context)
            val chosen = if (config.appSet.enabled) config.appSet.visible() else emptyList()

            views.setOnClickPendingIntent(R.id.widget_root, openPanel(context))
            views.setViewVisibility(R.id.widget_empty, if (chosen.isEmpty()) View.VISIBLE else View.GONE)

            for (index in slots.indices) {
                val packageName = chosen.getOrNull(index)
                if (packageName == null) {
                    views.setViewVisibility(slots[index], View.GONE)
                    continue
                }

                views.setViewVisibility(slots[index], View.VISIBLE)
                views.setTextViewText(labels[index], catalog.labelOf(packageName, config.settings.russifyLabels))

                val icon = catalog.icon(packageName)
                    ?.let { drawable -> runCatching { drawable.toBitmap(96, 96) }.getOrNull() }
                if (icon != null) views.setImageViewBitmap(icons[index], icon)

                views.setOnClickPendingIntent(slots[index], launch(context, packageName, index))
            }
            return views
        }

        /** Нажатие по значку открывает саму программу. */
        private fun launch(context: Context, packageName: String, index: Int): PendingIntent {
            val intent = runCatching { context.packageManager.getLaunchIntentForPackage(packageName) }
                .getOrNull()
                ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ?: return openPanel(context)

            return PendingIntent.getActivity(
                context,
                index + 1,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        /** Нажатие по пустому месту открывает панель — там набор и правится. */
        private fun openPanel(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        /** Сколько значков поместится в виджет. */
        fun capacity(): Int = AppSet.MAX
    }
}
