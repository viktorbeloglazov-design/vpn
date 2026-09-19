package ru.carpanel.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import ru.carpanel.model.Board
import ru.carpanel.model.PanelConfig
import ru.carpanel.model.Settings
import java.io.File

/**
 * Разложенная панель и настройки.
 *
 * Лежат одним файлом в приватном каталоге программы — переустановка поверх
 * (подпись та же) раскладку не теряет.
 */
class Store(context: Context) {

    private val file = File(context.filesDir, "panel.json")

    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = true
        encodeDefaults = true
    }

    private val _config = MutableStateFlow(read())
    val config: StateFlow<PanelConfig> = _config.asStateFlow()

    val board: Board get() = _config.value.board
    val settings: Settings get() = _config.value.settings

    private fun read(): PanelConfig = try {
        if (file.exists()) json.decodeFromString(PanelConfig.serializer(), file.readText()) else PanelConfig()
    } catch (error: Exception) {
        // Файл побился — начинаем с заводской раскладки, а не с пустого экрана.
        PanelConfig()
    }

    fun update(transform: (PanelConfig) -> PanelConfig) {
        val updated = transform(_config.value)
        _config.value = updated
        try {
            file.writeText(json.encodeToString(PanelConfig.serializer(), updated))
        } catch (error: Exception) {
            // На диск не легло, но в памяти уже применено: панель работает,
            // а следующая запись починит файл.
        }
    }

    fun updateBoard(transform: (Board) -> Board) = update { it.copy(board = transform(it.board)) }

    fun updateSettings(transform: (Settings) -> Settings) = update { it.copy(settings = transform(it.settings)) }
}
