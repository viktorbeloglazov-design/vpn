package kz.carlink.diag

import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri

/** Что из нужного для настоящего Android Auto уже стоит на телефоне. */
data class GoogleStatus(
    val framework: String? = null,
    val playServices: String? = null,
    val playStore: String? = null,
    val androidAuto: String? = null,
    val googleApp: String? = null,
    val deviceId: String? = null,
) {
    /** Всё на месте — машина увидит штатный Android Auto. */
    val ready: Boolean get() = playServices != null && playStore != null && androidAuto != null

    /** Сервисы есть, не хватает самого Android Auto. */
    val needsAuto: Boolean get() = playServices != null && playStore != null && androidAuto == null

    val deviceIdHex: String?
        get() = deviceId?.toLongOrNull()?.let { java.lang.Long.toHexString(it) }
}

/**
 * Проверка сервисов Google на телефоне.
 *
 * Нужна ровно для одного: показать, на каком шаге пути к настоящему Android
 * Auto телефон сейчас находится, и дать номер устройства для регистрации, если
 * прошивка не сертифицирована.
 */
object GoogleCheck {

    const val FRAMEWORK = "com.google.android.gsf"
    const val PLAY_SERVICES = "com.google.android.gms"
    const val PLAY_STORE = "com.android.vending"
    const val ANDROID_AUTO = "com.google.android.projection.gearhead"
    const val GOOGLE_APP = "com.google.android.googlequicksearchbox"

    const val REGISTRATION_URL = "https://www.google.com/android/uncertified/"

    fun read(context: Context): GoogleStatus = GoogleStatus(
        framework = version(context, FRAMEWORK),
        playServices = version(context, PLAY_SERVICES),
        playStore = version(context, PLAY_STORE),
        androidAuto = version(context, ANDROID_AUTO),
        googleApp = version(context, GOOGLE_APP),
        deviceId = deviceId(context),
    )

    private fun version(context: Context, packageName: String): String? = try {
        @Suppress("DEPRECATION")
        context.packageManager.getPackageInfo(packageName, 0).versionName ?: "есть"
    } catch (e: PackageManager.NameNotFoundException) {
        null
    } catch (e: Exception) {
        null
    }

    /**
     * Номер телефона в сервисах Google. Именно его вводят на странице
     * регистрации, когда прошивка не сертифицирована.
     */
    private fun deviceId(context: Context): String? = try {
        context.contentResolver.query(
            Uri.parse("content://com.google.android.gsf.gservices"),
            null,
            null,
            arrayOf("android_id"),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst() && cursor.columnCount >= 2) cursor.getString(1) else null
        }
    } catch (e: Exception) {
        // Провайдер отдаёт номер не всем; тогда его показывает любое
        // приложение вида «Device ID».
        null
    }
}
