package kz.carlink

import android.content.Context
import kz.carlink.aa.Pkcs12
import kz.carlink.projection.ProjectionMode
import java.io.File
import javax.net.ssl.KeyManager

/** Куда подключается телефон. */
enum class Transport { USB, DESK }

/** Настройки приложения: куда подключаться, что показывать и чем подписываться. */
object Settings {

    private const val PREFS = "carlink"
    private const val KEY_TRANSPORT = "transport"
    private const val KEY_HOST = "desk_host"
    private const val KEY_PORT = "desk_port"
    private const val KEY_MODE = "mode"
    private const val KEY_P12_PASSWORD = "p12_password"
    private const val CREDENTIALS_FILE = "credentials.p12"

    fun transport(context: Context): Transport {
        val name = prefs(context).getString(KEY_TRANSPORT, Transport.USB.name)
        return runCatching { Transport.valueOf(name!!) }.getOrDefault(Transport.USB)
    }

    fun setTransport(context: Context, transport: Transport) {
        prefs(context).edit().putString(KEY_TRANSPORT, transport.name).apply()
    }

    fun deskHost(context: Context): String = prefs(context).getString(KEY_HOST, "127.0.0.1") ?: "127.0.0.1"

    fun setDeskHost(context: Context, host: String) {
        prefs(context).edit().putString(KEY_HOST, host).apply()
    }

    fun deskPort(context: Context): Int = prefs(context).getInt(KEY_PORT, 5288)

    fun setDeskPort(context: Context, port: Int) {
        prefs(context).edit().putInt(KEY_PORT, port).apply()
    }

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
        Pkcs12.keyManagers(data, password)
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
            return Pkcs12.keyManagers(file.readBytes(), password)
        }
        return DeviceKey.keyManagers()
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
