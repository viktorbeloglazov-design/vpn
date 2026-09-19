package kz.carlink.headunit

import kz.carlink.aa.AudioConfig
import kz.carlink.aa.FrameCodec
import kz.carlink.aa.FrameSink
import kz.carlink.aa.Pkcs12
import kz.carlink.aa.Pointer
import kz.carlink.aa.Projection
import kz.carlink.aa.Session
import kz.carlink.aa.Stage
import kz.carlink.aa.TouchEvent
import kz.carlink.aa.VideoConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * Весь разговор целиком, без машины и без телефона: сторона телефона
 * ([Session]) и сторона головного устройства ([HeadUnit]) поднимаются в одном
 * процессе и соединяются обычным сокетом.
 *
 * Проверяется вся цепочка: запрос версии, рукопожатие TLS, список служб,
 * открытие каналов, согласование картинки, фокус экрана, поток кадров с
 * подтверждениями и касание в обратную сторону.
 */
class ProjectionEndToEndTest {

    private val log = StringBuilder()

    private fun note(side: String, line: String) {
        synchronized(log) { log.append(side).append(": ").append(line).append('\n') }
    }

    @Test(timeout = 90_000)
    fun phoneProjectsToHeadUnitAndReceivesTouch() {
        val server = ServerSocket(0, 1, InetAddress.getLoopbackAddress())
        val phoneSocket = Socket(InetAddress.getLoopbackAddress(), server.localPort)
        val headSocket = server.accept()
        phoneSocket.tcpNoDelay = true
        headSocket.tcpNoDelay = true

        val framesWanted = CountDownLatch(5)
        val framesSeen = AtomicInteger()
        val touchSeen = CountDownLatch(1)
        val gotTouch = AtomicReference<TouchEvent?>(null)
        val negotiated = AtomicReference<VideoConfig?>(null)
        val carName = AtomicReference("")

        val streaming = AtomicBoolean(true)

        val projection = object : Projection {
            override fun start(config: VideoConfig, sink: FrameSink) {
                negotiated.set(config)
                Thread({
                    var index = 0
                    while (streaming.get()) {
                        sink.onFrame(ByteArray(1024) { (it + index).toByte() }, index * 33_000L)
                        index++
                        Thread.sleep(10)
                    }
                }, "поддельный кодировщик").apply { isDaemon = true }.start()
            }

            override fun stop() {
                streaming.set(false)
            }

            override fun touch(event: TouchEvent, config: VideoConfig) {
                gotTouch.set(event)
                touchSeen.countDown()
            }
        }

        val keyManagers = Pkcs12.keyManagers(
            javaClass.classLoader!!.getResourceAsStream("handshake-test.p12")!!.use { it.readBytes() },
            "secret",
        )

        val session = Session(
            codec = FrameCodec(phoneSocket.getInputStream(), phoneSocket.getOutputStream()),
            keyManagers = keyManagers,
            projection = projection,
            audio = null,
            deviceName = "SM-W2026",
            deviceBrand = "Samsung",
            log = { note("телефон", it) },
            onStage = { stage, detail ->
                note("телефон", "этап ${stage.name} $detail")
                if (stage == Stage.DISCOVERY) carName.set(detail)
            },
        )

        val events = object : HeadUnitEvents {
            override fun log(line: String) = note("машина", line)
            override fun onPhone(name: String, brand: String) = note("машина", "телефон $brand $name")
            override fun onVideoStart(config: VideoConfig) = note("машина", "картинка пошла")
            override fun onVideoFrame(data: ByteArray, timestampUs: Long) {
                framesSeen.incrementAndGet()
                framesWanted.countDown()
            }

            override fun onAudioStart(config: AudioConfig) = Unit
            override fun onAudioFrame(data: ByteArray) = Unit
            override fun onClosed() = note("машина", "закрыто")
        }

        val headUnit = HeadUnit(
            FrameCodec(headSocket.getInputStream(), headSocket.getOutputStream()),
            CarProfile.taycan(1280, 720, 30),
            events,
        )

        val phoneThread = Thread(session, "телефон").apply { isDaemon = true; start() }
        val headThread = Thread(headUnit, "машина").apply { isDaemon = true; start() }

        try {
            assertTrue(
                "кадры до головного устройства не дошли\n$log",
                framesWanted.await(60, TimeUnit.SECONDS),
            )

            val config = negotiated.get()
            assertEquals("ширина картинки", 1280, config?.width)
            assertEquals("высота картинки", 720, config?.height)
            assertTrue("телефон не узнал машину: ${carName.get()}", carName.get().contains("Porsche"))

            headUnit.sendTouch(TouchEvent(TouchEvent.PRESS, 0, listOf(Pointer(640, 360, 0))))
            assertTrue("касание не дошло до телефона\n$log", touchSeen.await(20, TimeUnit.SECONDS))
            assertEquals(640, gotTouch.get()?.pointers?.first()?.x)
            assertEquals(360, gotTouch.get()?.pointers?.first()?.y)
        } finally {
            streaming.set(false)
            session.stop()
            headUnit.stop()
            runCatching { phoneSocket.close() }
            runCatching { headSocket.close() }
            runCatching { server.close() }
            phoneThread.join(2000)
            headThread.join(2000)
            println(log)
        }
    }
}
