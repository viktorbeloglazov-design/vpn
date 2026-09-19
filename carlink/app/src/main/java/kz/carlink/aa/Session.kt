package kz.carlink.aa

import kz.carlink.proto.ProtoDump
import javax.net.ssl.KeyManager

/** Куда уходят готовые куски потока: картинка и звук. */
interface FrameSink {
    fun onFrame(data: ByteArray, timestampUs: Long)
}

/** Источник картинки для экрана машины. */
interface Projection {
    fun start(config: VideoConfig, sink: FrameSink)
    fun stop()
    fun touch(event: TouchEvent, config: VideoConfig)
}

/** Источник звука для динамиков машины. */
interface AudioSource {
    fun start(config: AudioConfig, sink: FrameSink)
    fun stop()
}

/** Этап разговора — его показывает главный экран. */
enum class Stage(val title: String) {
    WAITING("Жду машину"),
    VERSION("Сверяем версии"),
    HANDSHAKE("Рукопожатие"),
    AUTHENTICATED("Машина приняла телефон"),
    DISCOVERY("Разбираю службы машины"),
    STREAMING("Картинка идёт"),
    CLOSED("Отключено"),
}

/**
 * Разговор с головным устройством: от запроса версии до потока картинки.
 *
 * Порядок такой. Машина шлёт запрос версии, телефон отвечает. Дальше машина
 * начинает рукопожатие TLS (она — клиент, телефон — сервер) и по его окончании
 * присылает AuthComplete. После этого спрашиваем список служб машины, открываем
 * нужные каналы, настраиваем картинку, просим фокус экрана — и отдаём поток.
 */
class Session(
    private val codec: FrameCodec,
    private val keyManagers: Array<KeyManager>,
    private val projection: Projection,
    private val audio: AudioSource?,
    private val deviceName: String,
    private val deviceBrand: String,
    private val log: (String) -> Unit,
    private val onStage: (Stage, String) -> Unit,
) : Runnable {

    @Volatile
    private var running = true

    private var ssl: SslLink? = null
    private var secure = false
    private var discovery: Discovery? = null
    private var videoService: Service? = null
    private var videoConfig: VideoConfig? = null
    private var audioService: Service? = null
    private var audioConfig: AudioConfig? = null
    private var videoStarted = false
    private var frames = 0L
    private var acks = 0L

    override fun run() {
        onStage(Stage.VERSION, "жду запрос версии от машины")
        try {
            while (running) {
                val message = codec.readMessage()
                if (message.channel == Control.CHANNEL) handleControl(message) else handleChannel(message)
            }
        } catch (e: Exception) {
            if (running) log("связь оборвалась: ${e.javaClass.simpleName}: ${e.message}")
        } finally {
            stopStreams()
            onStage(Stage.CLOSED, "соединение закрыто")
        }
    }

    fun stop() {
        running = false
        try {
            if (secure) send(Control.CHANNEL, Control.SHUTDOWN_REQUEST, Messages.shutdownRequest())
        } catch (e: Exception) {
            // Машину уже отсоединили — молчим.
        }
        stopStreams()
    }

    private fun stopStreams() {
        if (videoStarted) {
            videoStarted = false
            runCatching { projection.stop() }
        }
        runCatching { audio?.stop() }
    }

    // --- служебный канал -------------------------------------------------

    private fun handleControl(message: Message) {
        when (message.id) {
            Control.VERSION_REQUEST -> {
                val (major, minor) = Messages.parseVersion(message.payload)
                log("машина говорит на версии $major.$minor")
                sendPlain(Control.VERSION_RESPONSE, Messages.versionResponse(PROTOCOL_MAJOR, PROTOCOL_MINOR, true))
                onStage(Stage.HANDSHAKE, "проверяем сертификаты")
            }

            Control.SSL_HANDSHAKE -> {
                val link = ssl ?: SslLink(keyManagers).also { ssl = it }
                val answer = link.consumeHandshake(message.payload)
                if (answer.isNotEmpty()) sendPlain(Control.SSL_HANDSHAKE, answer)
                if (link.handshakeFinished && !secure) {
                    secure = true
                    codec.cryptor = link
                    log("рукопожатие прошло, шифр ${link.cipherSuite}")
                    link.peerCertificate?.let { log("сертификат машины: ${it.subjectX500Principal.name}") }
                    onStage(Stage.AUTHENTICATED, "машина приняла телефон")
                }
            }

            Control.AUTH_COMPLETE -> {
                log("машина подтвердила опознание, спрашиваю её службы")
                send(Control.CHANNEL, Control.SERVICE_DISCOVERY_REQUEST, Messages.serviceDiscoveryRequest(deviceName, deviceBrand))
            }

            Control.SERVICE_DISCOVERY_RESPONSE -> handleDiscovery(message.payload)

            Control.PING_REQUEST -> {
                val timestamp = System.nanoTime()
                send(Control.CHANNEL, Control.PING_RESPONSE, Messages.pingResponse(timestamp))
            }

            Control.AUDIO_FOCUS_REQUEST -> {
                send(Control.CHANNEL, Control.AUDIO_FOCUS_RESPONSE, Messages.audioFocusResponse(AUDIO_FOCUS_GAIN))
            }

            Control.NAVIGATION_FOCUS_REQUEST -> {
                send(Control.CHANNEL, Control.NAVIGATION_FOCUS_RESPONSE, Messages.navigationFocusResponse(2))
            }

            Control.SHUTDOWN_REQUEST -> {
                log("машина просит завершить сеанс")
                send(Control.CHANNEL, Control.SHUTDOWN_RESPONSE, Messages.shutdownResponse())
                running = false
            }

            Control.SHUTDOWN_RESPONSE -> running = false

            else -> log("служебное сообщение ${Control.name(message.id)}, ${message.payload.size} байт")
        }
    }

    private fun handleDiscovery(payload: ByteArray) {
        val found = try {
            Messages.parseDiscovery(payload)
        } catch (e: Exception) {
            log("не разобрал список служб: ${e.message}")
            log(ProtoDump.dump(payload))
            return
        }
        discovery = found
        log("подключено: ${found.headUnit.describe().ifBlank { "головное устройство без имени" }}")
        log("список служб машины целиком:\n" + ProtoDump.dump(payload))
        onStage(Stage.DISCOVERY, found.headUnit.describe())

        for (service in found.services) {
            val open = when (service.kind) {
                ServiceKind.VIDEO -> {
                    videoService = service
                    videoConfig = service.videoConfigs.maxByOrNull { it.width * it.height }
                    true
                }
                ServiceKind.INPUT -> true
                ServiceKind.SENSORS -> true
                ServiceKind.AUDIO -> {
                    // Музыку отдаём одним каналом — тем, что для медиа.
                    if (audio != null && service.audioKind == AudioKind.MEDIA) {
                        audioService = service
                        audioConfig = service.audioConfigs.maxByOrNull { it.sampleRate }
                        true
                    } else {
                        false
                    }
                }
                else -> false
            }
            log("канал ${service.channelId}: ${service.kind}" +
                (if (service.audioKind != AudioKind.UNKNOWN) " (${service.audioKind})" else "") +
                (if (open) " — открываю" else " — пропускаю"))
            if (open) send(service.channelId, Control.CHANNEL_OPEN_REQUEST, Messages.channelOpenRequest(service.channelId))
        }

        if (videoService == null) log("машина не предложила канал картинки — показывать нечего")
    }

    // --- каналы служб ----------------------------------------------------

    private fun handleChannel(message: Message) {
        val service = discovery?.services?.firstOrNull { it.channelId == message.channel }
        if (message.id == Control.CHANNEL_OPEN_RESPONSE) {
            val status = Messages.parseStatus(message.payload)
            log("канал ${message.channel} открыт (статус $status)")
            if (status == 0) onChannelOpened(service)
            return
        }
        when (service?.kind) {
            ServiceKind.VIDEO -> handleVideo(message)
            ServiceKind.AUDIO -> handleAudio(message)
            ServiceKind.INPUT -> handleInput(message)
            ServiceKind.SENSORS -> handleSensors(message)
            else -> log("канал ${message.channel}: сообщение 0x%04x, %d байт".format(message.id, message.payload.size))
        }
    }

    private fun onChannelOpened(service: Service?) {
        if (service == null) return
        when (service.kind) {
            ServiceKind.VIDEO -> {
                val config = videoConfig
                if (config == null) {
                    log("машина не назвала ни одного разрешения — беру 800×480")
                    videoConfig = VideoConfig(0, 1, 800, 480, 30, 160)
                }
                send(service.channelId, Av.SETUP_REQUEST, Messages.avSetupRequest(videoConfig!!.index))
            }
            ServiceKind.AUDIO -> {
                val index = audioConfig?.index ?: 0
                send(service.channelId, Av.SETUP_REQUEST, Messages.avSetupRequest(index))
            }
            ServiceKind.SENSORS -> {
                send(service.channelId, Sensors.START_REQUEST, Messages.sensorStartRequest(Sensors.TYPE_DRIVING_STATUS))
                send(service.channelId, Sensors.START_REQUEST, Messages.sensorStartRequest(Sensors.TYPE_NIGHT_DATA))
            }
            else -> Unit
        }
    }

    private fun handleVideo(message: Message) {
        val service = videoService ?: return
        when (message.id) {
            Av.SETUP_RESPONSE -> {
                val response = Messages.parseSetupResponse(message.payload)
                val config = videoConfig
                log("картинка согласована: статус ${response.status}, ${config?.width}×${config?.height} ${config?.fps} к/с")
                send(service.channelId, Av.VIDEO_FOCUS_REQUEST, Messages.videoFocusRequest(0, VIDEO_FOCUS_PROJECTED))
            }

            Av.VIDEO_FOCUS_INDICATION -> log("машина отдала экран приложению")

            Av.START_INDICATION -> {
                val start = Messages.parseStartIndication(message.payload)
                val config = videoConfig ?: return
                log("поехали: сеанс ${start.session}, показываю ${config.width}×${config.height}")
                videoStarted = true
                onStage(Stage.STREAMING, "${config.width}×${config.height}, ${config.fps} к/с")
                projection.start(config, object : FrameSink {
                    override fun onFrame(data: ByteArray, timestampUs: Long) {
                        if (!running) return
                        frames++
                        runCatching {
                            codec.writeMessage(
                                service.channelId,
                                Av.MEDIA_WITH_TIMESTAMP,
                                Messages.mediaWithTimestamp(timestampUs, data),
                                encrypted = true,
                                control = false,
                            )
                        }.onFailure { log("кадр не ушёл: ${it.message}") }
                    }
                })
            }

            Av.STOP_INDICATION -> {
                log("машина остановила картинку")
                videoStarted = false
                projection.stop()
            }

            Av.MEDIA_ACK -> acks++

            else -> log("канал картинки: ${Av.name(message.id)}")
        }
    }

    private fun handleAudio(message: Message) {
        val service = audioService ?: return
        when (message.id) {
            Av.SETUP_RESPONSE -> {
                log("звук согласован")
                send(Control.CHANNEL, Control.AUDIO_FOCUS_REQUEST, Messages.audioFocusRequest(AUDIO_FOCUS_GAIN))
            }
            Av.START_INDICATION -> {
                val config = audioConfig ?: AudioConfig(0, 48000, 16, 2)
                audio?.start(config, object : FrameSink {
                    override fun onFrame(data: ByteArray, timestampUs: Long) {
                        if (!running) return
                        runCatching {
                            codec.writeMessage(
                                service.channelId,
                                Av.MEDIA_WITH_TIMESTAMP,
                                Messages.mediaWithTimestamp(timestampUs, data),
                                encrypted = true,
                                control = false,
                            )
                        }
                    }
                })
            }
            Av.STOP_INDICATION -> audio?.stop()
            Av.MEDIA_ACK -> Unit
            else -> log("канал звука: ${Av.name(message.id)}")
        }
    }

    private fun handleInput(message: Message) {
        if (message.id != Input.EVENT_INDICATION) return
        val touch = try {
            Messages.parseTouch(message.payload)
        } catch (e: Exception) {
            null
        }
        val config = videoConfig
        if (touch == null || config == null) return
        projection.touch(touch, config)
    }

    private fun handleSensors(message: Message) {
        when (message.id) {
            Sensors.START_RESPONSE -> Unit
            Sensors.EVENT_INDICATION -> Unit
            else -> log("канал датчиков: 0x%04x".format(message.id))
        }
    }

    // --- отправка --------------------------------------------------------

    private fun sendPlain(id: Int, payload: ByteArray) =
        codec.writeMessage(Control.CHANNEL, id, payload, encrypted = false, control = true)

    private fun send(channel: Int, id: Int, payload: ByteArray) =
        codec.writeMessage(channel, id, payload, encrypted = secure, control = true)

    fun statistics(): String = "кадров отправлено $frames, подтверждено $acks"

    companion object {
        const val PROTOCOL_MAJOR = 1
        const val PROTOCOL_MINOR = 1

        /** Экран отдан проекции, а не собственному интерфейсу машины. */
        const val VIDEO_FOCUS_PROJECTED = 1
        const val AUDIO_FOCUS_GAIN = 1
    }
}
