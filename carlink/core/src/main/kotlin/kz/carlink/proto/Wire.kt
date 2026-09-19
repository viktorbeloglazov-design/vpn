package kz.carlink.proto

import java.io.ByteArrayOutputStream

/**
 * Минимальный кодек protobuf.
 *
 * Android Auto разговаривает сообщениями protobuf, но описаний (.proto) Google
 * не публикует. Тянуть ради этого генератор кода незачем: формат «поле —
 * значение» простой, и своя реализация даёт две вещи, которых нет у
 * сгенерированного кода, — она не падает на незнакомых полях и умеет показать
 * чужое сообщение целиком (см. [ProtoDump]), когда номера полей у конкретной
 * машины отличаются от ожидаемых.
 */
class ProtoWriter {
    private val out = ByteArrayOutputStream()

    fun varint(field: Int, value: Long): ProtoWriter {
        tag(field, 0)
        writeVarint(value)
        return this
    }

    fun int32(field: Int, value: Int): ProtoWriter = varint(field, value.toLong())

    fun bool(field: Int, value: Boolean): ProtoWriter = varint(field, if (value) 1L else 0L)

    fun fixed64(field: Int, value: Long): ProtoWriter {
        tag(field, 1)
        for (i in 0 until 8) out.write(((value ushr (8 * i)) and 0xFF).toInt())
        return this
    }

    fun bytes(field: Int, value: ByteArray): ProtoWriter {
        tag(field, 2)
        writeVarint(value.size.toLong())
        out.write(value, 0, value.size)
        return this
    }

    fun string(field: Int, value: String): ProtoWriter = bytes(field, value.toByteArray(Charsets.UTF_8))

    fun message(field: Int, body: ProtoWriter.() -> Unit): ProtoWriter {
        val nested = ProtoWriter()
        nested.body()
        return bytes(field, nested.toByteArray())
    }

    fun toByteArray(): ByteArray = out.toByteArray()

    private fun tag(field: Int, wireType: Int) = writeVarint(((field shl 3) or wireType).toLong())

    private fun writeVarint(value: Long) {
        var rest = value
        while (true) {
            if (rest and 0x7FL.inv() == 0L) {
                out.write(rest.toInt())
                return
            }
            out.write(((rest and 0x7F) or 0x80L).toInt())
            rest = rest ushr 7
        }
    }
}

/**
 * Чтение сообщения. Порядок работы: [next] переходит к следующему полю, дальше
 * читается значение нужного типа. Непрочитанное поле пропускается само, так что
 * неизвестные поля не мешают разбору.
 */
class ProtoReader(
    private val buf: ByteArray,
    private var pos: Int = 0,
    private val limit: Int = buf.size,
) {
    var field: Int = 0
        private set
    var wireType: Int = 0
        private set

    private var consumed = true

    fun next(): Boolean {
        if (!consumed) skipValue()
        if (pos >= limit) return false
        val tag = readVarint().toInt()
        field = tag ushr 3
        wireType = tag and 7
        consumed = false
        return field != 0
    }

    fun varint(): Long {
        consumed = true
        return readVarint()
    }

    fun int32(): Int = varint().toInt()

    fun bool(): Boolean = varint() != 0L

    fun bytes(): ByteArray {
        consumed = true
        val len = readVarint().toInt()
        require(len >= 0 && pos + len <= limit) { "поле $field выходит за границы сообщения" }
        val value = buf.copyOfRange(pos, pos + len)
        pos += len
        return value
    }

    fun string(): String = String(bytes(), Charsets.UTF_8)

    fun nested(): ProtoReader {
        consumed = true
        val len = readVarint().toInt()
        require(len >= 0 && pos + len <= limit) { "вложенное поле $field выходит за границы сообщения" }
        val reader = ProtoReader(buf, pos, pos + len)
        pos += len
        return reader
    }

    fun fixed64(): Long {
        consumed = true
        require(pos + 8 <= limit) { "поле $field выходит за границы сообщения" }
        var value = 0L
        for (i in 0 until 8) value = value or ((buf[pos + i].toLong() and 0xFF) shl (8 * i))
        pos += 8
        return value
    }

    fun skipValue() {
        consumed = true
        when (wireType) {
            0 -> readVarint()
            1 -> pos += 8
            // Сначала длина (она сама двигает позицию), только потом переход.
            2 -> {
                val length = readVarint().toInt()
                pos += length
            }
            5 -> pos += 4
            else -> pos = limit
        }
        if (pos > limit) pos = limit
    }

    private fun readVarint(): Long {
        var result = 0L
        var shift = 0
        while (shift < 64) {
            require(pos < limit) { "сообщение оборвалось на разборе числа" }
            val b = buf[pos++].toInt()
            result = result or ((b and 0x7F).toLong() shl shift)
            if (b and 0x80 == 0) return result
            shift += 7
        }
        throw IllegalArgumentException("слишком длинное число в поле $field")
    }
}
