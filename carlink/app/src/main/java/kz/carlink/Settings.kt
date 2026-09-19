package kz.carlink

import android.content.Context
import kz.carlink.aa.Credentials
import kz.carlink.projection.ProjectionMode
import java.io.File
import javax.net.ssl.KeyManager

/** Настройки приложения: как показывать экран и чем подписываться. */
object Settings {

    private const val PREFS = "carlink"
    private const val KEY_MODE = "mode"
    private const val KEY_P12_PASSWORD = "p12_password"
    private const val CREDENTIALS_FILE = "credentials.p12"

    fun mode(context: Context): ProjectionMode {
        val name = prefs(context).getString(KEY_MODE, ProjectionMode.CAR_UI.name)
        return runCatching { ProjectionMode.valueOf(name!!) }.getOrDefault(ProjectionMode.CAR_UI)
    }

    fun setMode(context: Context, mode: ProjectionMode) {
        prefs(context).edit().putString(KEY_MODE, mode.name).apply()
    }

    fun credentialsFile(context: Context): File = File(context.filesDir, CREDENTIALS_FILE)

    fun hasCredentials(context: Context): Boolean = credentialsFile(context).exists()

    fun saveCredentials(context: Context, data: ByteArray, password: String) {
        // Проверяем сразу: лучше узнать о неверном пароле здесь, чем в машине.
        Credentials.fromPkcs12(data, password)
        credentialsFile(context).writeBytes(data)
        prefs(context).edit().putString(KEY_P12_PASSWORD, password).apply()
    }

    fun forgetCredentials(context: Context) {
        credentialsFile(context).delete()
        prefs(context).edit().remove(KEY_P12_PASSWORD).apply()
    }

    /**
     * Ключ для рукопожатия с машиной. Если своего файла нет, берётся
     * отладочный самоподписанный — настоящая машина его не примет.
     */
    fun keyManagers(context: Context): Array<KeyManager> {
        val file = credentialsFile(context)
        if (file.exists()) {
            val password = prefs(context).getString(KEY_P12_PASSWORD, "") ?: ""
            return Credentials.fromPkcs12(file.readBytes(), password)
        }
        return Credentials.developmentKey()
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
