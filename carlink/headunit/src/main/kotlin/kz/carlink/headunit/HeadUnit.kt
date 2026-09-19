package kz.carlink.headunit

import kz.carlink.aa.AudioConfig
import kz.carlink.aa.AudioKind
import kz.carlink.aa.Av
import kz.carlink.aa.Control
import kz.carlink.aa.FrameCodec
import kz.carlink.aa.HeadUnit as HeadUnitInfo
import kz.carlink.aa.Input
import kz.carlink.aa.Messages
import kz.carlink.aa.Sensors
import kz.carlink.aa.Service
import kz.carlink.aa.ServiceKind
import kz.carlink.aa.SslLink
import kz.carlink.aa.TouchEvent
import kz.carlink.aa.VideoConfig

/** Каким головным устройством притворяемся. */
data class CarProfile(
    val info: HeadUnitInfo,
    val services: List<Service>,
) {
    val video: Service? get() = services.firstOrNull { it.kind == ServiceKind.VIDEO }
    val audio: Service? get() = services.firstOrNull { it.kind == ServiceKind.AUDIO }
    val input: Service? get() = services.firstOrNull { it.kind == ServiceKind.INPUT }

    companion object {
        /** Профиль под Taycan: широкий экран и обычный для машины звук. */
        fun taycan(width: Int, height: Int, fps: Int): CarProfile {
            val resolution = resolutionCode(width, height)
            return CarProfile(
                info = HeadUnitInfo(
                    name = "CarLink Desk",
                    carModel = "Taycan",
                    carYear = "2021",
                    serial = "DESK-0001",
                    manufacturer = "Porsche",
                    model = "PCM 6.0",
                    softwareBuild = "desk",
                    softwareVersion = "1.0",
                ),
                services = listOf(
                    Service(1, ServiceKind.SENSORS),
                    Service(
                        2,
                        ServiceKind.VIDEO,
                        videoConfigs = listOf(VideoConfig(0, resolution, width, height, fps, 160)),
                    ),
                    Service(
                        3,
                        ServiceKind.AUDIO,
                        audioKind = AudioKind.MEDIA,
                        audioConfigs = listOf(AudioConfig(0, 48000, 16, 2)),
                    ),
                    Service(
                        4,
                        ServiceKind.INPUT,
                        videoConfigs = listOf(VideoConfig(0, resolution, width, height, fps, 160)),
                    ),
                ),
            )
        }

        private fun resolutionCode(width: Int, height: Int): Int = when {
            width == 800 && height == 480 -> 1
            width == 1920 && height == 1080 -> 3
            width == 2560 && height == 1440 -> 4
            width == 1920 && height == 1200 -> 5
            else -> 2
        }
    }
}

/** Что эмулятор сообщает наружу — окну, динамику, журналу. */
interface HeadUnitEvents {
    fun log(line: String)
    fun onPhone(name: String, brand: String)
    fun onVideoStart(config: VideoConfig)
    fun onVideoFrame(data: ByteArray, timestampUs: Long)
    fun onAudioStart(config: AudioConfig)
    fun onAudioFrame(data: ByteArray)
    fun onClosed()
}

/**
 * Сторона головного устройства.
 *
 * Зеркало [kz.carlink.aa.Session]: разговор начинает эмулятор запросом версии,
 * он же клиент TLS и он же рассказывает телефону, какие у машины есть каналы.
 * Сертификат телефона не проверяется — в этом весь смысл стенда: отладочный
 * ключ здесь проходит, а в машине нет.
 */
class HeadUnit(
    private val codec: FrameCodec,
    private val profile: CarProfile,
    private val events: HeadUnitEvents,
) : Runnable {

    private val ssl = SslLink(emptyArray(), clientMode = true)

    @Volatile
    private var running = true

    private var secure = false
    private var videoSession = 1
    private var frames = 0L
    private var bytes = 0L

    override fun run() {
        try {
            events.log("здороваюсь с телефоном")
            sendPlain(Control.VERSION_REQUEST, Messages.versionRequest())
            while (running) {
                val message = codec.readMessage()
                if (message.channel == Control.CHANNEL) handleControl(message.id, message.payload)
                else handleChannel(message.channel, message.id, message.payload)
            }
        } catch (e: Exception) {
            if (running) events.log("связь оборвалась: ${e.javaClass.simpleName}: ${e.message}")
        } finally {
            events.log("принято кадров: $frames, ${bytes / 1024} КиБ")
            events.onClosed()
        }
    }

    fun stop() {
        running = false
    }

    /** Отправляет касание так, как это делает сенсорный экран машины. */
    fun sendTouch(event: TouchEvent) {
        val channel = profile.input?.channelId ?: return
        if (!secure) return
        runCatching {
            codec.writeMessage(
                channel,
                Input.EVENT_INDICATION,
                Messages.inputEvent(System.nanoTime() / 1000, event),
                encrypted = true,
                control = false,
            )
        }.onFailure { events.log("касание не ушло: ${it.message}") }
    }

    private fun handleControl(id: Int, payload: ByteArray) {
        when (id) {
            Control.VERSION_RESPONSE -> {
                val (major, minor) = Messages.parseVersion(payload)
                events.log("телефон говорит на версии $major.$minor, начинаю рукопожатие")
                val hello = ssl.startHandshake()
                if (hello.isNotEmpty()) sendPlain(Control.SSL_HANDSHAKE, hello)
            }

            Control.SSL_HANDSHAKE -> {
                val answer = ssl.consumeHandshake(payload)
                if (answer.isNotEmpty()) sendPlain(Control.SSL_HANDSHAKE, answer)
                if (ssl.handshakeFinished && !secure) {
                    secure = true
                    codec.cryptor = ssl
                    events.log("рукопожатие прошло, шифр ${ssl.cipherSuite}")
                    ssl.peerCertificate?.let { events.log("сертификат телефона: ${it.subjectX500Principal.name}") }
                    send(Control.CHANNEL, Control.AUTH_COMPLETE, Messages.authComplete())
                }
            }

            Control.SERVICE_DISCOVERY_REQUEST -> {
                val (name, brand) = Messages.parseServiceDiscoveryRequest(payload)
                events.log("подключился телефон: $brand $name")
                events.onPhone(name, brand)
                send(
                    Control.CHANNEL,
                    Control.SERVICE_DISCOVERY_RESPONSE,
                    Messages.serviceDiscoveryResponse(profile.info, profile.services),
                )
            }

            Control.AUDIO_FOCUS_REQUEST ->
                send(Control.CHANNEL, Control.AUDIO_FOCUS_RESPONSE, Messages.audioFocusResponse(1))

            Control.NAVIGATION_FOCUS_REQUEST ->
                send(Control.CHANNEL, Control.NAVIGATION_FOCUS_RESPONSE, Messages.navigationFocusResponse(2))

            Control.PING_RESPONSE -> Unit

            Control.SHUTDOWN_REQUEST -> {
                events.log("телефон завершает сеанс")
                send(Control.CHANNEL, Control.SHUTDOWN_RESPONSE, Messages.shutdownResponse())
                running = false
            }

            else -> events.log("служебное сообщение ${Control.name(id)}")
        }
    }

    private fun handleChannel(channel: Int, id: Int, payload: ByteArray) {
        if (id == Control.CHANNEL_OPEN_REQUEST) {
            events.log("телефон открывает канал $channel")
            send(channel, Control.CHANNEL_OPEN_RESPONSE, Messages.channelOpenResponse(0))
            return
        }
        when (channel) {
            profile.video?.channelId -> handleVideo(channel, id, payload)
            profile.audio?.channelId -> handleAudio(channel, id, payload)
            else -> when (id) {
                Sensors.START_REQUEST -> send(channel, Sensors.START_RESPONSE, Messages.sensorStartResponse())
                else -> Unit
            }
        }
    }

    private fun handleVideo(channel: Int, id: Int, payload: ByteArray) {
        val config = profile.video?.videoConfigs?.firstOrNull() ?: return
        when (id) {
            Av.SETUP_REQUEST -> {
                val index = Messages.parseSetupRequest(payload)
                events.log("телефон просит настройку картинки №$index")
                send(channel, Av.SETUP_RESPONSE, Messages.setupResponse(0, 1, listOf(index)))
            }

            Av.VIDEO_FOCUS_REQUEST -> {
                val mode = Messages.parseVideoFocusRequest(payload)
                send(channel, Av.VIDEO_FOCUS_INDICATION, Messages.videoFocusIndication(mode))
                send(channel, Av.START_INDICATION, Messages.startIndication(videoSession, config.index))
                events.log("отдал экран телефону: ${config.width}×${config.height}")
                events.onVideoStart(config)
            }

            Av.MEDIA_WITH_TIMESTAMP, Av.MEDIA -> {
                val (timestamp, data) = if (id == Av.MEDIA_WITH_TIMESTAMP) {
                    Messages.parseMediaWithTimestamp(payload)
                } else {
                    0L to payload
                }
                frames++
                bytes += data.size
                events.onVideoFrame(data, timestamp)
                send(channel, Av.MEDIA_ACK, Messages.mediaAck(videoSession))
            }

            else -> events.log("канал картинки: ${Av.name(id)}")
        }
    }

    private fun handleAudio(channel: Int, id: Int, payload: ByteArray) {
        val config = profile.audio?.audioConfigs?.firstOrNull() ?: return
        when (id) {
            Av.SETUP_REQUEST -> {
                val index = Messages.parseSetupRequest(payload)
                send(channel, Av.SETUP_RESPONSE, Messages.setupResponse(0, 1, listOf(index)))
                send(channel, Av.START_INDICATION, Messages.startIndication(videoSession, index))
                events.log("жду звук: ${config.sampleRate} Гц")
                events.onAudioStart(config)
            }

            Av.MEDIA_WITH_TIMESTAMP, Av.MEDIA -> {
                val data = if (id == Av.MEDIA_WITH_TIMESTAMP) {
                    Messages.parseMediaWithTimestamp(payload).second
                } else {
                    payload
                }
                events.onAudioFrame(data)
                send(channel, Av.MEDIA_ACK, Messages.mediaAck(videoSession))
            }

            else -> Unit
        }
    }

    private fun sendPlain(id: Int, payload: ByteArray) =
        codec.writeMessage(Control.CHANNEL, id, payload, encrypted = false, control = true)

    private fun send(channel: Int, id: Int, payload: ByteArray) =
        codec.writeMessage(channel, id, payload, encrypted = secure, control = true)
}
