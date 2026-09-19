package kz.qpvpn.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kz.qpvpn.model.AppConfig
import java.io.File

/**
 * Настройки и профиль подключения.
 *
 * Оба файла лежат в приватном каталоге приложения: другие программы их не видят.
 */
class Store(context: Context) {

    private val configFile = File(context.filesDir, "config.json")
    private val profileFile = File(context.filesDir, "profile.conf")

    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = true
        encodeDefaults = true
    }

    private val _config = MutableStateFlow(readConfig())
    val config: StateFlow<AppConfig> = _config.asStateFlow()

    private fun readConfig(): AppConfig = try {
        if (configFile.exists()) json.decodeFromString(AppConfig.serializer(), configFile.readText())
        else AppConfig()
    } catch (error: Exception) {
        AppConfig()
    }

    fun update(transform: (AppConfig) -> AppConfig) {
        val updated = transform(_config.value)
        _config.value = updated
        try {
            configFile.writeText(json.encodeToString(AppConfig.serializer(), updated))
        } catch (error: Exception) {
            // Настройки не сохранились на диск, но в памяти уже применены:
            // туннель перестроится, а при следующей записи файл починится сам.
        }
    }

    val hasProfile: Boolean get() = profileFile.exists() && profileFile.length() > 0

    fun profileText(): String? = if (hasProfile) profileFile.readText() else null

    fun saveProfile(text: String) {
        profileFile.writeText(text)
        profileFile.setReadable(false, false)
        profileFile.setReadable(true, true)
    }

    fun clearProfile() {
        profileFile.delete()
    }
}
