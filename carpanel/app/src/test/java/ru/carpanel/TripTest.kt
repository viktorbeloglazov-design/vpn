package ru.carpanel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import ru.carpanel.drive.Fix
import ru.carpanel.drive.TripMath
import ru.carpanel.drive.TripState

class TripTest {

    private fun fix(
        seconds: Long,
        lat: Double = 55.7500,
        lon: Double = 37.6100,
        speed: Float? = null,
        accuracy: Float = 5f,
    ) = Fix(timeMs = seconds * 1000L, lat = lat, lon = lon, speedMs = speed, accuracyM = accuracy)

    @Test
    fun `расстояние считается по дуге земли`() {
        val meters = TripMath.distance(fix(0), fix(1, lat = 55.7600))
        assertEquals(1112.0, meters, 5.0)
    }

    @Test
    fun `скорость берётся у приёмника`() {
        assertEquals(14f, TripMath.speed(null, fix(1, speed = 14f)), 0.001f)
    }

    @Test
    fun `скорость считается сама, если приёмник молчит`() {
        val previous = fix(0)
        val next = fix(10, lat = 55.7510)
        // 0,001 градуса широты — примерно 111 метров, значит около 11 м/с.
        assertEquals(11.1f, TripMath.speed(previous, next), 0.5f)
    }

    @Test
    fun `выдумки приёмника отбрасываются`() {
        assertEquals(0f, TripMath.speed(null, fix(1, speed = 400f)), 0.001f)
    }

    @Test
    fun `неточное показание не меняет поездку`() {
        val state = TripState(distanceM = 100.0)
        val after = TripMath.update(state, fix(5, accuracy = 120f))
        assertEquals(state, after)
    }

    @Test
    fun `движение прибавляет путь и время`() {
        var state = TripMath.update(TripState(), fix(0, speed = 15f))
        state = TripMath.update(state, fix(1, lat = 55.750135, speed = 15f))
        assertEquals(15.0, state.distanceM, 2.0)
        assertEquals(1000L, state.movingMs)
        assertEquals(15f, state.maxSpeedMs, 0.001f)
    }

    @Test
    fun `на стоянке метры не наматываются`() {
        var state = TripMath.update(TripState(), fix(0))
        repeat(10) { step ->
            state = TripMath.update(state, fix(1L + step, lat = 55.7500 + step * 0.0000010))
        }
        assertEquals(0.0, state.distanceM, 0.001)
        assertEquals(0L, state.movingMs)
    }

    @Test
    fun `длинный перерыв не дорисовывает путь`() {
        var state = TripMath.update(TripState(), fix(0, speed = 20f))
        state = TripMath.update(state, fix(600, lat = 55.8000, speed = 20f))
        assertEquals(0.0, state.distanceM, 0.001)
        assertTrue(state.lastFix != null)
    }

    @Test
    fun `средняя скорость считается по времени в движении`() {
        val state = TripState(distanceM = 1000.0, movingMs = 100_000L)
        assertEquals(10f, TripMath.averageMs(state), 0.001f)
        assertEquals(0f, TripMath.averageMs(TripState()), 0.001f)
    }

    @Test
    fun `метры в секунду переводятся в привычные единицы`() {
        assertEquals(36, TripMath.kmh(10f))
        assertEquals(22, TripMath.mph(10f))
        assertEquals(0, TripMath.kmh(0f))
    }

    @Test
    fun `начало поездки запоминается по первому показанию`() {
        val state = TripMath.update(TripState(), fix(42, speed = 10f))
        assertEquals(42_000L, state.startedAtMs)
    }
}
