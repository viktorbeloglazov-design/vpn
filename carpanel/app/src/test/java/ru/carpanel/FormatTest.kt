package ru.carpanel

import org.junit.Assert.assertEquals
import org.junit.Test
import ru.carpanel.ui.Format

class FormatTest {

    @Test
    fun `скорость показывается целым числом`() {
        assertEquals("36", Format.speed(10f))
        assertEquals("22", Format.speed(10f, miles = true))
        assertEquals("0", Format.speed(-5f))
    }

    @Test
    fun `короткий путь остаётся в метрах`() {
        assertEquals("840 м", Format.distance(840.0))
        assertEquals("0 м", Format.distance(0.0))
    }

    @Test
    fun `длинный путь показывается в километрах`() {
        assertEquals("12,3 км", Format.distance(12_345.0))
        assertEquals("1,0 км", Format.distance(1_000.0))
    }

    @Test
    fun `время в пути читается без секунд`() {
        assertEquals("0 мин", Format.duration(0L))
        assertEquals("12 мин", Format.duration(12 * 60_000L))
        assertEquals("1 ч 05 мин", Format.duration(65 * 60_000L))
        assertEquals("30 с", Format.duration(30_000L))
    }

    @Test
    fun `единицы подписываются по выбору`() {
        assertEquals("км/ч", Format.speedUnit())
        assertEquals("миль/ч", Format.speedUnit(miles = true))
    }
}
