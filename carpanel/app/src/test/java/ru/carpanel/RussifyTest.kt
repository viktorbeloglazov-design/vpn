package ru.carpanel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import ru.carpanel.apps.Russify
import ru.carpanel.model.Defaults

class RussifyTest {

    @Test
    fun `китайские названия переводятся`() {
        assertEquals("Настройки", Russify.translate("设置"))
        assertEquals("Музыка", Russify.translate("音乐"))
        assertEquals("Видеорегистратор", Russify.translate("行车记录仪"))
    }

    @Test
    fun `английские названия переводятся без оглядки на регистр`() {
        assertEquals("Настройки", Russify.translate("Settings"))
        assertEquals("Настройки", Russify.translate("SETTINGS"))
        assertEquals("Файлы", Russify.translate("  File Manager  "))
    }

    @Test
    fun `незнакомое название остаётся как было`() {
        assertEquals("Ozon", Russify.translate("Ozon"))
        assertEquals("电子狗助手", Russify.translate("电子狗助手"))
        assertEquals("", Russify.translate(null))
        assertEquals("", Russify.translate("   "))
    }

    @Test
    fun `известная программа берёт название из своего списка`() {
        assertEquals("Яндекс Навигатор", Russify.label(Defaults.NAVIGATOR, "Yandex Navigator"))
        assertEquals("Яндекс Музыка", Russify.label(Defaults.MUSIC, "音乐"))
    }

    @Test
    fun `чужая программа переводится по словарю`() {
        assertEquals("Камера", Russify.label("com.example.camera", "相机"))
        assertEquals("Ozon", Russify.label("ru.ozon.app.android", "Ozon"))
    }

    @Test
    fun `словарь знает, что умеет переводить`() {
        assertTrue(Russify.has("设置"))
        assertTrue(Russify.has("gallery"))
        assertFalse(Russify.has("Ozon"))
        assertFalse(Russify.has(null))
    }
}
