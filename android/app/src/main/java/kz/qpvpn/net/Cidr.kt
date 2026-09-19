package kz.qpvpn.net

/** Подсеть IPv4: адрес начала и длина префикса. */
data class Ipv4Net(val start: Long, val prefix: Int) {
    val size: Long get() = 1L shl (32 - prefix)
    val endInclusive: Long get() = start + size - 1

    override fun toString(): String {
        val a = (start shr 24) and 0xFF
        val b = (start shr 16) and 0xFF
        val c = (start shr 8) and 0xFF
        val d = start and 0xFF
        return "$a.$b.$c.$d/$prefix"
    }
}

/**
 * Разбор адресов и арифметика подсетей.
 *
 * Android не умеет «исключающие» маршруты: туннелю задаётся список того, что
 * в него заходит. Поэтому режим «всё кроме правил» считается как дополнение —
 * всё адресное пространство минус исключённые подсети.
 */
object Cidr {

    fun isIpv4(value: String): Boolean = parseAddress(value) != null

    fun parseAddress(value: String): Long? {
        val parts = value.trim().split(".")
        if (parts.size != 4) return null
        var result = 0L
        for (part in parts) {
            if (part.isEmpty() || part.length > 3 || !part.all { it.isDigit() }) return null
            val number = part.toInt()
            if (number > 255) return null
            if (part.length > 1 && part[0] == '0') return null
            result = (result shl 8) or number.toLong()
        }
        return result
    }

    /** Принимает «10.0.0.0/8» и одиночный «1.2.3.4» (станет /32). */
    fun parse(value: String): Ipv4Net? {
        val text = value.trim()
        val slash = text.indexOf('/')
        if (slash < 0) {
            val address = parseAddress(text) ?: return null
            return Ipv4Net(address, 32)
        }
        val address = parseAddress(text.substring(0, slash)) ?: return null
        val prefixPart = text.substring(slash + 1)
        val prefix = prefixPart.toIntOrNull() ?: return null
        if (prefix < 0 || prefix > 32) return null
        val mask = if (prefix == 0) 0L else ((1L shl (32 - prefix)) - 1).inv() and 0xFFFFFFFFL
        return Ipv4Net(address and mask, prefix)
    }

    fun isDomain(value: String): Boolean {
        val text = value.trim().lowercase()
        if (text.isEmpty() || text.length > 253 || !text.contains('.')) return false
        if (text.startsWith(".") || text.endsWith(".") || text.contains("..")) return false
        if (!text.all { it.isLetterOrDigit() && it.code < 128 || it == '.' || it == '-' }) return false
        return text.split(".").all { label ->
            label.isNotEmpty() && label.length <= 63 && !label.startsWith("-") && !label.endsWith("-")
        }
    }

    /** Ошибка правила для показа пользователю либо null. */
    fun ruleError(kind: kz.qpvpn.model.RuleKind, value: String): String? {
        val text = value.trim()
        if (text.isEmpty()) return "Пустое значение."
        return when (kind) {
            kz.qpvpn.model.RuleKind.DOMAIN ->
                if (isDomain(text)) null else "«$text» не похоже на домен (пример: kaspi.kz)."
            kz.qpvpn.model.RuleKind.CIDR ->
                if (parse(text) != null) null else "«$text» не похоже на IP или подсеть (пример: 92.46.0.0/16)."
        }
    }

    /** Схлопывает пересекающиеся и соседние подсети. */
    fun merge(nets: List<Ipv4Net>): List<Ipv4Net> {
        if (nets.isEmpty()) return emptyList()
        val ranges = nets.map { it.start to it.endInclusive }.sortedBy { it.first }
        val merged = mutableListOf<Pair<Long, Long>>()
        for (range in ranges) {
            val last = merged.lastOrNull()
            if (last != null && range.first <= last.second + 1) {
                merged[merged.size - 1] = last.first to maxOf(last.second, range.second)
            } else {
                merged.add(range)
            }
        }
        return merged.flatMap { rangeToNets(it.first, it.second) }
    }

    /** Всё адресное пространство минус перечисленные подсети. */
    fun complement(excluded: List<Ipv4Net>): List<Ipv4Net> {
        if (excluded.isEmpty()) return listOf(Ipv4Net(0, 0))

        val ranges = excluded.map { it.start to it.endInclusive }.sortedBy { it.first }
        val merged = mutableListOf<Pair<Long, Long>>()
        for (range in ranges) {
            val last = merged.lastOrNull()
            if (last != null && range.first <= last.second + 1) {
                merged[merged.size - 1] = last.first to maxOf(last.second, range.second)
            } else {
                merged.add(range)
            }
        }

        val result = mutableListOf<Ipv4Net>()
        var cursor = 0L
        for ((start, end) in merged) {
            if (start > cursor) {
                result += rangeToNets(cursor, start - 1)
            }
            cursor = maxOf(cursor, end + 1)
            if (cursor > 0xFFFFFFFFL) break
        }
        if (cursor <= 0xFFFFFFFFL) {
            result += rangeToNets(cursor, 0xFFFFFFFFL)
        }
        return result
    }

    /** Наименьший набор подсетей, покрывающий диапазон адресов целиком. */
    fun rangeToNets(start: Long, endInclusive: Long): List<Ipv4Net> {
        val result = mutableListOf<Ipv4Net>()
        var current = start
        while (current <= endInclusive) {
            // Самый крупный блок, который начинается здесь и не вылезает за конец.
            var prefix = 32
            while (prefix > 0) {
                val candidate = prefix - 1
                val size = 1L shl (32 - candidate)
                if (current % size != 0L || current + size - 1 > endInclusive) break
                prefix = candidate
            }
            result += Ipv4Net(current, prefix)
            current += 1L shl (32 - prefix)
        }
        return result
    }
}
