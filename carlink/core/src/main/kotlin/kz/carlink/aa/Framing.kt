package kz.carlink.aa

import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream

/** Готовое сообщение: номер канала, номер сообщения и полезная нагрузка. */
class Message(val channel: Int, val id: Int, val payload: ByteArray)

/** Шифрование полезной нагрузки кадра. До завершения рукопожатия его нет. */
interface Cryptor {
    fun encrypt(plain: ByteArray): ByteArray
    fun decrypt(cipher: ByteArray): ByteArray
}

/**
 * Кадрирование Android Auto.
 *
 * Заголовок кадра — четыре байта: номер канала, флаги, длина полезной нагрузки
 * (два байта, старший первым). У первого кадра длинного сообщения после
 * заголовка идут ещё четыре байта — общая длина всех кусков. Сообщение длиннее
 * [MAX_PAYLOAD] режется на куски, каждый шифруется отдельно.
 *
 * Первые два байта собранного сообщения — его номер.
 */
class FrameCodec(
    private val input: InputStream,
    private val output: OutputStream,
) {
    @Volatile
    var cryptor: Cryptor? = null

    private val partial = HashMap<Int, ByteArrayOutputStream>()
    private val writeLock = Any()

    /** Читает кадры, пока не соберётся целое сообщение. */
    fun readMessage(): Message {
        while (true) {
            val header = readFully(4)
            val channel = header[0].toInt() and 0xFF
            val flags = header[1].toInt() and 0xFF
            val size = ((header[2].toInt() and 0xFF) shl 8) or (header[3].toInt() and 0xFF)

            val type = flags and 0x03
            if (type == FRAME_FIRST) {
                // Общая длина сообщения. Мы собираем по кадрам, так что она нужна
                // только для проверки — читаем и не используем.
                readFully(4)
            }

            var payload = readFully(size)
            if (flags and FLAG_ENCRYPTED != 0) {
                val cryptor = this.cryptor ?: throw IllegalStateException(
                    "машина прислала шифрованный кадр до рукопожатия"
                )
                payload = cryptor.decrypt(payload)
            }

            val complete: ByteArray = when (type) {
                FRAME_BULK -> payload
                FRAME_FIRST -> {
                    partial[channel] = ByteArrayOutputStream().apply { write(payload) }
                    continue
                }
                FRAME_MIDDLE -> {
                    partial.getOrPut(channel) { ByteArrayOutputStream() }.write(payload)
                    continue
                }
                else -> {
                    val buffer = partial.remove(channel)
                    if (buffer == null) payload else buffer.apply { write(payload) }.toByteArray()
                }
            }

            if (complete.size < 2) continue
            val id = ((complete[0].toInt() and 0xFF) shl 8) or (complete[1].toInt() and 0xFF)
            return Message(channel, id, complete.copyOfRange(2, complete.size))
        }
    }

    /**
     * Отправляет сообщение, при необходимости разрезав его на кадры.
     *
     * @param control служебное сообщение канала (настройка, фокус, открытие),
     *   в отличие от потока звука и картинки.
     */
    fun writeMessage(
        channel: Int,
        id: Int,
        payload: ByteArray,
        encrypted: Boolean,
        control: Boolean,
    ) {
        val full = ByteArray(payload.size + 2)
        full[0] = ((id shr 8) and 0xFF).toByte()
        full[1] = (id and 0xFF).toByte()
        System.arraycopy(payload, 0, full, 2, payload.size)

        // Шифрование внутри замка: SSLEngine не рассчитан на то, что его
        // зовут из двух потоков сразу, а кадры шлют и приёмная петля, и
        // кодировщик картинки.
        synchronized(writeLock) {
            val chunks = ArrayList<ByteArray>()
            var offset = 0
            while (offset < full.size) {
                val end = minOf(offset + MAX_PAYLOAD, full.size)
                val chunk = full.copyOfRange(offset, end)
                chunks += if (encrypted) {
                    val cryptor = this.cryptor ?: throw IllegalStateException("шифрование ещё не готово")
                    cryptor.encrypt(chunk)
                } else {
                    chunk
                }
                offset = end
            }
            if (chunks.isEmpty()) chunks += ByteArray(0)
            val totalSize = chunks.sumOf { it.size }
            chunks.forEachIndexed { index, chunk ->
                val first = index == 0
                val last = index == chunks.size - 1
                var flags = when {
                    first && last -> FRAME_BULK
                    first -> FRAME_FIRST
                    last -> FRAME_LAST
                    else -> FRAME_MIDDLE
                }
                if (control) flags = flags or FLAG_CONTROL
                if (encrypted) flags = flags or FLAG_ENCRYPTED

                val header = ByteArrayOutputStream(8)
                header.write(channel and 0xFF)
                header.write(flags)
                header.write((chunk.size shr 8) and 0xFF)
                header.write(chunk.size and 0xFF)
                if (first && !last) {
                    header.write((totalSize ushr 24) and 0xFF)
                    header.write((totalSize ushr 16) and 0xFF)
                    header.write((totalSize ushr 8) and 0xFF)
                    header.write(totalSize and 0xFF)
                }
                output.write(header.toByteArray())
                output.write(chunk)
            }
            output.flush()
        }
    }

    private fun readFully(length: Int): ByteArray {
        val buffer = ByteArray(length)
        var read = 0
        while (read < length) {
            val n = input.read(buffer, read, length - read)
            if (n < 0) throw EOFException("машина закрыла соединение")
            read += n
        }
        return buffer
    }

    companion object {
        const val MAX_PAYLOAD = 0x4000

        const val FRAME_MIDDLE = 0
        const val FRAME_FIRST = 1
        const val FRAME_LAST = 2
        const val FRAME_BULK = 3

        const val FLAG_CONTROL = 0x04
        const val FLAG_ENCRYPTED = 0x08
    }
}
