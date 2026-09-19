package kz.qpvpn.ui

import java.util.Locale

object Format {

    fun bytes(value: Long): String {
        val units = listOf("Б", "КБ", "МБ", "ГБ", "ТБ")
        var size = value.toDouble()
        var index = 0
        while (size >= 1024 && index < units.size - 1) {
            size /= 1024
            index++
        }
        return if (index == 0) "$value Б"
        else String.format(Locale.getDefault(), "%.1f %s", size, units[index])
    }

    fun duration(sinceMillis: Long): String {
        if (sinceMillis <= 0) return "—"
        val seconds = ((System.currentTimeMillis() - sinceMillis) / 1000).coerceAtLeast(0)
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        val rest = seconds % 60
        return when {
            hours > 0 -> String.format(Locale.getDefault(), "%d ч %02d мин", hours, minutes)
            minutes > 0 -> String.format(Locale.getDefault(), "%d мин %02d с", minutes, rest)
            else -> "$rest с"
        }
    }
}
