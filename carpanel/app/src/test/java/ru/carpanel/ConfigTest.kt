package ru.carpanel

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import ru.carpanel.apps.KnownApps
import ru.carpanel.model.Defaults
import ru.carpanel.model.PanelConfig
import ru.carpanel.model.TileKind

class ConfigTest {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    @Test
    fun `раскладка переживает запись и чтение`() {
        val config = PanelConfig()
        val restored = json.decodeFromString(
            PanelConfig.serializer(),
            json.encodeToString(PanelConfig.serializer(), config),
        )
        assertEquals(config, restored)
    }

    @Test
    fun `чужие поля в файле не мешают`() {
        val text = """{"board":{"columns":4,"rows":2,"tiles":[]},"settings":{},"мусор":1}"""
        val config = json.decodeFromString(PanelConfig.serializer(), text)
        assertEquals(4, config.board.columns)
        assertTrue(config.board.tiles.isEmpty())
        assertTrue(config.settings.keepScreenOn)
    }

    @Test
    fun `в заводской раскладке есть навигатор, музыка и спидометр`() {
        val board = Defaults.board()
        assertTrue(board.tiles.any { it.packageName == Defaults.NAVIGATOR })
        assertTrue(board.tiles.any { it.packageName == Defaults.MUSIC })
        assertTrue(board.tiles.any { it.kind == TileKind.SPEED })
    }

    @Test
    fun `известные программы знают свои запасные ссылки`() {
        assertEquals("Яндекс Навигатор", KnownApps.label(Defaults.NAVIGATOR))
        assertEquals("yandexnavi://", KnownApps.fallbackUri(Defaults.NAVIGATOR))
        assertEquals(null, KnownApps.fallbackUri("com.example.unknown"))
        assertTrue(KnownApps.isKnown(Defaults.MUSIC))
    }
}
