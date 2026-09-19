package ru.carpanel.ui

import ru.carpanel.drive.TripMath
import java.util.Locale

/**
 * Подписи на плитках.
 *
 * Без Android внутри: за русские запятые и склейку единиц отвечают тесты.
 */
object Format {

    private val ru: Locale = Locale.forLanguageTag("ru")

    /** Скорость целым числом: на ходу дробь только мешает. */
    fun speed(speedMs: Float, miles: Boolean = false): String =
        (if (miles) TripMath.mph(speedMs) else TripMath.kmh(speedMs)).coerceAtLeast(0).toString()

    fun speedUnit(miles: Boolean = false): String = if (miles) "миль/ч" else "км/ч"

    /** Путь: до километра — в метрах, дальше — с одним знаком после запятой. */
    fun distance(meters: Double, miles: Boolean = false): String {
        if (meters.isNaN() || meters < 0) return "0 м"
        if (miles) {
            val value = meters / 1609.344
            return if (value < 0.1) "${(meters * 3.28084).toInt()} фт" else String.format(ru, "%.1f миль", value)
        }
        if (meters < 1000) return "${meters.toInt()} м"
        return String.format(ru, "%.1f км", meters / 1000.0)
    }

    /** Время в пути: «5 мин», «1 ч 05 мин». */
    fun duration(millis: Long): String {
        if (millis <= 0L) return "0 мин"
        val totalMinutes = millis / 60_000L
        val hours = totalMinutes / 60
        val minutes = totalMinutes % 60
        if (hours <= 0L) {
            if (totalMinutes <= 0L) return "${(millis / 1000L).coerceAtLeast(1)} с"
            return "$totalMinutes мин"
        }
        return String.format(ru, "%d ч %02d мин", hours, minutes)
    }
}
