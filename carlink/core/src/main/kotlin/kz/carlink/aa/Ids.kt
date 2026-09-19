package kz.carlink.aa

/**
 * Номера сообщений Android Auto.
 *
 * Значения взяты из открытых реализаций головных устройств (aasdk/openauto) —
 * там они получены разбором трафика. Google описаний не публикует, поэтому всё,
 * что приходит с неизвестным номером, попадает в журнал как есть.
 */
object Control {
    const val CHANNEL = 0

    const val VERSION_REQUEST = 0x0001
    const val VERSION_RESPONSE = 0x0002
    const val SSL_HANDSHAKE = 0x0003
    const val AUTH_COMPLETE = 0x0004
    const val SERVICE_DISCOVERY_REQUEST = 0x0005
    const val SERVICE_DISCOVERY_RESPONSE = 0x0006
    const val CHANNEL_OPEN_REQUEST = 0x0007
    const val CHANNEL_OPEN_RESPONSE = 0x0008
    const val PING_REQUEST = 0x000B
    const val PING_RESPONSE = 0x000C
    const val NAVIGATION_FOCUS_REQUEST = 0x000D
    const val NAVIGATION_FOCUS_RESPONSE = 0x000E
    const val SHUTDOWN_REQUEST = 0x000F
    const val SHUTDOWN_RESPONSE = 0x0010
    const val VOICE_SESSION_REQUEST = 0x0011
    const val AUDIO_FOCUS_REQUEST = 0x0012
    const val AUDIO_FOCUS_RESPONSE = 0x0013

    fun name(id: Int): String = when (id) {
        VERSION_REQUEST -> "VersionRequest"
        VERSION_RESPONSE -> "VersionResponse"
        SSL_HANDSHAKE -> "SslHandshake"
        AUTH_COMPLETE -> "AuthComplete"
        SERVICE_DISCOVERY_REQUEST -> "ServiceDiscoveryRequest"
        SERVICE_DISCOVERY_RESPONSE -> "ServiceDiscoveryResponse"
        CHANNEL_OPEN_REQUEST -> "ChannelOpenRequest"
        CHANNEL_OPEN_RESPONSE -> "ChannelOpenResponse"
        PING_REQUEST -> "PingRequest"
        PING_RESPONSE -> "PingResponse"
        NAVIGATION_FOCUS_REQUEST -> "NavigationFocusRequest"
        NAVIGATION_FOCUS_RESPONSE -> "NavigationFocusResponse"
        SHUTDOWN_REQUEST -> "ShutdownRequest"
        SHUTDOWN_RESPONSE -> "ShutdownResponse"
        AUDIO_FOCUS_REQUEST -> "AudioFocusRequest"
        AUDIO_FOCUS_RESPONSE -> "AudioFocusResponse"
        else -> "0x%04x".format(id)
    }
}

/** Сообщения канала звука и картинки. */
object Av {
    const val MEDIA_WITH_TIMESTAMP = 0x0000
    const val MEDIA = 0x0001
    const val SETUP_REQUEST = 0x8000
    const val START_INDICATION = 0x8001
    const val STOP_INDICATION = 0x8002
    const val SETUP_RESPONSE = 0x8003
    const val MEDIA_ACK = 0x8004
    const val VIDEO_FOCUS_REQUEST = 0x8005
    const val VIDEO_FOCUS_INDICATION = 0x8006

    fun name(id: Int): String = when (id) {
        MEDIA_WITH_TIMESTAMP -> "MediaWithTimestamp"
        MEDIA -> "Media"
        SETUP_REQUEST -> "SetupRequest"
        START_INDICATION -> "StartIndication"
        STOP_INDICATION -> "StopIndication"
        SETUP_RESPONSE -> "SetupResponse"
        MEDIA_ACK -> "MediaAck"
        VIDEO_FOCUS_REQUEST -> "VideoFocusRequest"
        VIDEO_FOCUS_INDICATION -> "VideoFocusIndication"
        else -> "0x%04x".format(id)
    }
}

/** Сообщения канала ввода: касания и кнопки руля. */
object Input {
    const val EVENT_INDICATION = 0x8001
    const val BINDING_REQUEST = 0x8002
    const val BINDING_RESPONSE = 0x8003
}

/** Сообщения канала датчиков машины. */
object Sensors {
    const val START_REQUEST = 0x8001
    const val START_RESPONSE = 0x8002
    const val EVENT_INDICATION = 0x8003

    const val TYPE_NIGHT_DATA = 10
    const val TYPE_DRIVING_STATUS = 13
}

/** Что умеет канал, о котором рассказала машина. */
enum class ServiceKind { SENSORS, VIDEO, AUDIO, MICROPHONE, INPUT, BLUETOOTH, NAVIGATION, OTHER }

/** Назначение звукового канала: музыка, подсказки навигатора, системные звуки. */
enum class AudioKind(val streamType: Int) { MEDIA(1), SPEECH(2), SYSTEM(3), UNKNOWN(0) }
