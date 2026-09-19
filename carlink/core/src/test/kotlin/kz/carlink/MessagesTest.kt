package kz.carlink

import kz.carlink.aa.AudioKind
import kz.carlink.aa.Messages
import kz.carlink.aa.ServiceKind
import kz.carlink.aa.TouchEvent
import kz.carlink.proto.ProtoWriter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MessagesTest {

    /** Собираем ответ так, как его прислало бы головное устройство. */
    private fun discoveryResponse(): ByteArray = ProtoWriter()
        .message(1) {
            int32(1, 1)
            message(2) { int32(1, 1) } // датчики
        }
        .message(1) {
            int32(1, 2)
            message(3) {
                int32(1, 3) // поток картинки
                message(4) {
                    int32(1, 2) // 1280×720
                    int32(2, 1) // 30 кадров
                    int32(5, 160)
                }
                message(4) {
                    int32(1, 1) // 800×480
                    int32(2, 1)
                    int32(5, 160)
                }
            }
        }
        .message(1) {
            int32(1, 3)
            message(3) {
                int32(1, 1) // поток звука
                int32(2, 1) // музыка
                message(3) {
                    int32(1, 48000)
                    int32(2, 16)
                    int32(3, 2)
                }
            }
        }
        .message(1) {
            int32(1, 4)
            message(4) { int32(1, 1) } // ввод
        }
        .string(2, "PCM")
        .string(3, "Taycan")
        .string(7, "Porsche")
        .string(10, "6.0.1")
        .toByteArray()

    @Test
    fun parsesServiceDiscovery() {
        val discovery = Messages.parseDiscovery(discoveryResponse())

        assertEquals("PCM", discovery.headUnit.name)
        assertEquals("Taycan", discovery.headUnit.carModel)
        assertEquals("Porsche", discovery.headUnit.manufacturer)
        assertTrue(discovery.headUnit.describe().contains("Porsche"))

        val video = discovery.services.first { it.kind == ServiceKind.VIDEO }
        assertEquals(2, video.channelId)
        assertEquals(2, video.videoConfigs.size)
        val best = video.videoConfigs.maxByOrNull { it.width * it.height }!!
        assertEquals(1280, best.width)
        assertEquals(720, best.height)
        assertEquals(30, best.fps)

        val audio = discovery.services.first { it.kind == ServiceKind.AUDIO }
        assertEquals(AudioKind.MEDIA, audio.audioKind)
        assertEquals(48000, audio.audioConfigs.first().sampleRate)

        assertEquals(ServiceKind.SENSORS, discovery.services.first { it.channelId == 1 }.kind)
        assertEquals(ServiceKind.INPUT, discovery.services.first { it.channelId == 4 }.kind)
    }

    @Test
    fun versionResponseIsSixBytes() {
        val response = Messages.versionResponse(1, 1, matched = true)
        assertEquals(6, response.size)
        assertEquals(1, response[1].toInt())
        assertEquals(1, response[3].toInt())
        assertEquals(0, response[5].toInt())

        val mismatch = Messages.versionResponse(1, 1, matched = false)
        assertEquals(0xFF, mismatch[4].toInt() and 0xFF)
    }

    @Test
    fun parsesVersionRequest() {
        val (major, minor) = Messages.parseVersion(byteArrayOf(0, 1, 0, 2))
        assertEquals(1, major)
        assertEquals(2, minor)
    }

    @Test
    fun parsesTouchEvent() {
        val payload = ProtoWriter()
            .varint(1, 123456789L)
            .message(3) {
                message(1) {
                    int32(1, 640)
                    int32(2, 360)
                    int32(3, 0)
                }
                int32(2, 0)
                int32(3, TouchEvent.DRAG)
            }
            .toByteArray()

        val touch = Messages.parseTouch(payload)
        assertNotNull(touch)
        assertEquals(TouchEvent.DRAG, touch!!.action)
        assertEquals(640, touch.pointers.first().x)
        assertEquals(360, touch.pointers.first().y)
    }

    @Test
    fun mediaChunkStartsWithTimestamp() {
        val data = Messages.mediaWithTimestamp(0x0102030405060708L, byteArrayOf(0x11, 0x22))
        assertEquals(10, data.size)
        assertEquals(0x01, data[0].toInt())
        assertEquals(0x08, data[7].toInt())
        assertEquals(0x11, data[8].toInt())
    }
}
