package ru.carpanel.drive

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/** Одно показание GPS. */
data class Fix(
    val timeMs: Long,
    val lat: Double,
    val lon: Double,
    /** Скорость от приёмника, если он её сообщил, м/с. */
    val speedMs: Float? = null,
    /** Заявленная точность, метры. */
    val accuracyM: Float = 0f,
)

/** Накопленное за поездку. */
data class TripState(
    val distanceM: Double = 0.0,
    val maxSpeedMs: Float = 0f,
    /** Время в движении, без стоянок на светофорах. */
    val movingMs: Long = 0L,
    val startedAtMs: Long = 0L,
    val lastFix: Fix? = null,
)

/**
 * Счёт скорости и пути по показаниям GPS.
 *
 * Отдельно от Android, чтобы правила отсева кривых показаний можно было
 * проверить тестами, а не на дороге.
 */
object TripMath {

    /** Показания хуже этой точности не берём: в тоннеле и под мостом они врут. */
    const val WORST_ACCURACY_M = 50f

    /** Разрыв больше этого — машина стояла или приёмник молчал, путь не дорисовываем. */
    const val MAX_GAP_MS = 15_000L

    /** Ниже этой скорости считаем, что стоим: так GPS не «наматывает» метры на стоянке. */
    const val STANDING_MS = 1.0f

    /** Выше этого показание считаем ошибкой приёмника: 90 м/с — это 324 км/ч. */
    const val ABSURD_SPEED_MS = 90f

    private const val EARTH_RADIUS_M = 6_371_000.0

    /** Расстояние между двумя точками по поверхности земли, метры. */
    fun distance(a: Fix, b: Fix): Double {
        val lat1 = Math.toRadians(a.lat)
        val lat2 = Math.toRadians(b.lat)
        val dLat = Math.toRadians(b.lat - a.lat)
        val dLon = Math.toRadians(b.lon - a.lon)
        val h = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * EARTH_RADIUS_M * atan2(sqrt(h), sqrt(1 - h))
    }

    /** Скорость: от приёмника, а если он её не дал — из пройденного за время между показаниями. */
    fun speed(previous: Fix?, next: Fix): Float {
        next.speedMs?.let { reported ->
            if (reported >= 0f && reported < ABSURD_SPEED_MS) return reported
        }
        val prev = previous ?: return 0f
        val seconds = (next.timeMs - prev.timeMs) / 1000.0
        if (seconds <= 0.0 || seconds > MAX_GAP_MS / 1000.0) return 0f
        val derived = (distance(prev, next) / seconds).toFloat()
        return if (derived < ABSURD_SPEED_MS) max(0f, derived) else 0f
    }

    /** Принять очередное показание. Негодное вернёт прежнее состояние. */
    fun update(state: TripState, next: Fix): TripState {
        if (next.accuracyM > WORST_ACCURACY_M) return state
        if (abs(next.lat) > 90.0 || abs(next.lon) > 180.0) return state

        val started = if (state.startedAtMs == 0L) next.timeMs else state.startedAtMs
        val previous = state.lastFix
            ?: return state.copy(startedAtMs = started, lastFix = next)

        val gap = next.timeMs - previous.timeMs
        if (gap <= 0L || gap > MAX_GAP_MS) {
            return state.copy(startedAtMs = started, lastFix = next)
        }

        val current = speed(previous, next)
        val moving = current >= STANDING_MS
        val step = if (moving) distance(previous, next) else 0.0

        return state.copy(
            distanceM = state.distanceM + step,
            maxSpeedMs = max(state.maxSpeedMs, current),
            movingMs = state.movingMs + if (moving) gap else 0L,
            startedAtMs = started,
            lastFix = next,
        )
    }

    /** Средняя скорость за время в движении, м/с. */
    fun averageMs(state: TripState): Float {
        val seconds = state.movingMs / 1000.0
        if (seconds <= 0.0) return 0f
        return (state.distanceM / seconds).toFloat()
    }

    /** Километры в час целым числом — как на приборной панели. */
    fun kmh(speedMs: Float): Int = (speedMs * 3.6f).roundToInt()

    /** Мили в час: на случай, если так привычнее. */
    fun mph(speedMs: Float): Int = (speedMs * 2.236936f).roundToInt()
}
