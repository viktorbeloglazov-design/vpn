package kz.carlink

import kz.carlink.aa.Cryptor
import kz.carlink.aa.FrameCodec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Test

class FramingTest {

    private fun roundTrip(
        channel: Int,
        id: Int,
        payload: ByteArray,
        cryptor: Cryptor? = null,
    ): Triple<Int, Int, ByteArray> {
        val wire = ByteArrayOutputStream()
        val writer = FrameCodec(ByteArrayInputStream(ByteArray(0)), wire)
        writer.cryptor = cryptor
        writer.writeMessage(channel, id, payload, encrypted = cryptor != null, control = true)

        val reader = FrameCodec(ByteArrayInputStream(wire.toByteArray()), ByteArrayOutputStream())
        reader.cryptor = cryptor
        val message = reader.readMessage()
        return Triple(message.channel, message.id, message.payload)
    }

    @Test
    fun shortMessageFitsOneFrame() {
        val payload = byteArrayOf(1, 2, 3, 4, 5)
        val (channel, id, result) = roundTrip(3, 0x8001, payload)
        assertEquals(3, channel)
        assertEquals(0x8001, id)
        assertArrayEquals(payload, result)
    }

    @Test
    fun longMessageIsSplitAndReassembled() {
        val payload = ByteArray(100_000) { (it % 251).toByte() }
        val (_, id, result) = roundTrip(2, 0x0000, payload)
        assertEquals(0x0000, id)
        assertArrayEquals(payload, result)
    }

    @Test
    fun encryptedFramesRoundTrip() {
        val xor = object : Cryptor {
            override fun encrypt(plain: ByteArray) = ByteArray(plain.size) { (plain[it].toInt() xor 0x5A).toByte() }
            override fun decrypt(cipher: ByteArray) = encrypt(cipher)
        }
        val payload = ByteArray(40_000) { (it % 97).toByte() }
        val (_, _, result) = roundTrip(1, 0x0005, payload, xor)
        assertArrayEquals(payload, result)
    }

    @Test
    fun headerCarriesControlAndEncryptionFlags() {
        val wire = ByteArrayOutputStream()
        val codec = FrameCodec(ByteArrayInputStream(ByteArray(0)), wire)
        codec.writeMessage(0, 0x0005, byteArrayOf(9), encrypted = false, control = true)
        val bytes = wire.toByteArray()
        assertEquals(0, bytes[0].toInt())
        val flags = bytes[1].toInt()
        assertEquals(FrameCodec.FRAME_BULK, flags and 0x03)
        assertTrue(flags and FrameCodec.FLAG_CONTROL != 0)
        assertEquals(0, flags and FrameCodec.FLAG_ENCRYPTED)
        // Длина: номер сообщения (2 байта) плюс сам байт полезной нагрузки.
        assertEquals(3, ((bytes[2].toInt() and 0xFF) shl 8) or (bytes[3].toInt() and 0xFF))
    }
}
