package ru.carpanel.apps

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Drawable
import android.net.Uri
import ru.carpanel.model.Tile

/** Установленная программа: чем подписать плитку и что запускать. */
data class AppEntry(
    val packageName: String,
    val className: String?,
    val label: String,
)

/** Список программ в машине и запуск выбранной. */
class AppCatalog(private val context: Context) {

    private val pm: PackageManager get() = context.packageManager

    /**
     * Всё, что показывает система в своём меню программ, по алфавиту.
     *
     * При [russify] китайские и английские названия заменяются русскими из
     * словаря — прошивка машины сама этого не делает.
     */
    fun installed(russify: Boolean = true): List<AppEntry> {
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return runCatching { pm.queryIntentActivities(launcher, 0) }
            .getOrDefault(emptyList())
            .mapNotNull { resolved ->
                val activity = resolved.activityInfo ?: return@mapNotNull null
                if (activity.packageName == context.packageName) return@mapNotNull null
                AppEntry(
                    packageName = activity.packageName,
                    className = activity.name,
                    label = label(activity.packageName, runCatching { resolved.loadLabel(pm).toString() }.getOrNull(), russify),
                )
            }
            .distinctBy { it.packageName }
            .sortedBy { it.label.lowercase() }
    }

    /** Известные программы для машины, которых ещё нет в системе. */
    fun suggestions(): List<AppEntry> {
        val present = installed(russify = false).map { it.packageName }.toSet()
        return KnownApps.list
            .filterNot { present.contains(it.packageName) }
            .map { AppEntry(it.packageName, null, it.label) }
    }

    fun isInstalled(packageName: String?): Boolean {
        val name = packageName ?: return false
        return runCatching { pm.getPackageInfo(name, 0) }.isSuccess
    }

    fun icon(packageName: String?): Drawable? {
        val name = packageName ?: return null
        return runCatching { pm.getApplicationIcon(name) }.getOrNull()
    }

    /** Подпись плитки: переименованная хозяином, затем системная или из словаря. */
    fun label(tile: Tile, russify: Boolean = true): String {
        tile.label?.takeIf { it.isNotBlank() }?.let { return it }
        val name = tile.packageName ?: return "Программа"
        return labelOf(name, russify)
    }

    /** Название программы по имени пакета. */
    fun labelOf(packageName: String, russify: Boolean = true): String {
        val fromSystem = runCatching { pm.getApplicationInfo(packageName, 0).loadLabel(pm).toString() }.getOrNull()
        return label(packageName, fromSystem, russify)
    }

    private fun label(packageName: String, fromSystem: String?, russify: Boolean): String {
        val system = fromSystem?.takeIf { it.isNotBlank() }
        if (russify) return Russify.label(packageName, system ?: packageName)
        return system ?: KnownApps.label(packageName) ?: packageName
    }

    /**
     * Открыть программу плитки.
     *
     * Сначала обычный запуск по имени пакета, затем — точный экран, если он
     * записан в плитке, и в последнюю очередь ссылка вида `yandexnavi://`:
     * некоторые программы прячут значок, но ссылку понимают.
     */
    fun launch(tile: Tile): Boolean {
        val name = tile.packageName ?: return false

        val byPackage = runCatching { pm.getLaunchIntentForPackage(name) }.getOrNull()
        if (start(byPackage)) return true

        val exact = tile.className?.let { className ->
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .setClassName(name, className)
        }
        if (start(exact)) return true

        val uri = KnownApps.fallbackUri(name) ?: return false
        return start(Intent(Intent.ACTION_VIEW, Uri.parse(uri)).setPackage(name))
    }

    private fun start(intent: Intent?): Boolean {
        val target = intent ?: return false
        target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching { context.startActivity(target) }.isSuccess
    }
}
