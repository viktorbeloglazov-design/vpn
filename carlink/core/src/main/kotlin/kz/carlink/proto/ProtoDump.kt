package kz.carlink.proto

/**
 * Показывает любое сообщение protobuf деревом «номер поля — значение».
 *
 * Пригодится там, где описания сообщений нет: в журнале видно, что именно
 * прислала машина, и номера полей в [kz.carlink.aa.Messages] можно поправить по
 * факту, не гадая.
 */
object ProtoDump {

    fun dump(data: ByteArray, indent: String = ""): String {
        val sb = StringBuilder()
        render(ProtoReader(data), indent, sb, depth = 0)
        return sb.toString()
    }

    private fun render(reader: ProtoReader, indent: String, sb: StringBuilder, depth: Int) {
        try {
            while (reader.next()) {
                val field = reader.field
                when (reader.wireType) {
                    0 -> sb.append(indent).append("#$field = ").append(reader.varint()).append('\n')
                    1 -> sb.append(indent).append("#$field = 0x")
                        .append(java.lang.Long.toHexString(reader.fixed64())).append('\n')
                    2 -> {
                        val value = reader.bytes()
                        val nested = if (depth < 6) tryNested(value, indent, depth) else null
                        when {
                            nested != null -> {
                                sb.append(indent).append("#$field {\n").append(nested).append(indent).append("}\n")
                            }
                            isText(value) -> sb.append(indent).append("#$field = \"")
                                .append(String(value, Charsets.UTF_8)).append("\"\n")
                            else -> sb.append(indent).append("#$field = ").append(value.size)
                                .append(" байт ").append(hex(value, 16)).append('\n')
                        }
                    }
                    else -> {
                        sb.append(indent).append("#$field = ?\n")
                        reader.skipValue()
                    }
                }
            }
        } catch (e: Exception) {
            sb.append(indent).append("… разбор прерван: ").append(e.message).append('\n')
        }
    }

    /**
     * Считаем поле вложенным сообщением, только если оно разбирается ровно до
     * последнего байта. Иначе короткая строка вроде «PCM» превращается в
     * бессмысленное дерево: её байты тоже похожи на номера полей.
     */
    private fun tryNested(value: ByteArray, indent: String, depth: Int): String? {
        if (value.size < 2) return null
        if (!parsesExactly(value)) return null
        val sb = StringBuilder()
        render(ProtoReader(value), "$indent  ", sb, depth + 1)
        return if (sb.contains("разбор прерван")) null else sb.toString()
    }

    private fun parsesExactly(value: ByteArray): Boolean {
        var pos = 0
        var fields = 0
        while (pos < value.size) {
            val tag = readVarint(value, pos) ?: return false
            pos = tag.second
            val field = (tag.first ushr 3).toInt()
            if (field == 0) return false
            when ((tag.first and 7L).toInt()) {
                0 -> pos = (readVarint(value, pos) ?: return false).second
                1 -> pos += 8
                2 -> {
                    val length = readVarint(value, pos) ?: return false
                    pos = length.second + length.first.toInt()
                    if (length.first < 0) return false
                }
                5 -> pos += 4
                else -> return false
            }
            if (pos > value.size) return false
            fields++
        }
        return fields > 0
    }

    /** Возвращает значение и позицию за ним либо null, если число не помещается. */
    private fun readVarint(value: ByteArray, start: Int): Pair<Long, Int>? {
        var result = 0L
        var shift = 0
        var pos = start
        while (shift < 64) {
            if (pos >= value.size) return null
            val b = value[pos++].toInt()
            result = result or ((b and 0x7F).toLong() shl shift)
            if (b and 0x80 == 0) return result to pos
            shift += 7
        }
        return null
    }

    private fun isText(value: ByteArray): Boolean =
        value.isNotEmpty() && value.all { it >= 0x20 || it == 0x0A.toByte() }

    fun hex(data: ByteArray, max: Int = Int.MAX_VALUE): String {
        val shown = minOf(data.size, max)
        val sb = StringBuilder(shown * 3)
        for (i in 0 until shown) {
            sb.append(String.format("%02x", data[i]))
            if (i != shown - 1) sb.append(' ')
        }
        if (shown < data.size) sb.append(" …")
        return sb.toString()
    }
}
