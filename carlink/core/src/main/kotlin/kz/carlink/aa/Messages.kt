package kz.carlink.aa

import kz.carlink.proto.ProtoReader
import kz.carlink.proto.ProtoWriter

data class HeadUnit(
    val name: String = "",
    val carModel: String = "",
    val carYear: String = "",
    val serial: String = "",
    val manufacturer: String = "",
    val model: String = "",
    val softwareBuild: String = "",
    val softwareVersion: String = "",
    val leftHandDrive: Boolean = true,
) {
    fun describe(): String = buildString {
        append(listOf(manufacturer, model, name).filter { it.isNotBlank() }.joinToString(" "))
        if (carModel.isNotBlank()) append(" · $carModel")
        if (carYear.isNotBlank()) append(" $carYear")
        if (softwareVersion.isNotBlank()) append(" · ПО $softwareVersion")
    }.trim()
}

data class VideoConfig(
    val index: Int,
    val resolutionCode: Int,
    val width: Int,
    val height: Int,
    val fps: Int,
    val dpi: Int,
)

data class AudioConfig(
    val index: Int,
    val sampleRate: Int,
    val bitDepth: Int,
    val channels: Int,
)

data class Service(
    val channelId: Int,
    val kind: ServiceKind,
    val audioKind: AudioKind = AudioKind.UNKNOWN,
    val videoConfigs: List<VideoConfig> = emptyList(),
    val audioConfigs: List<AudioConfig> = emptyList(),
)

data class Discovery(val headUnit: HeadUnit, val services: List<Service>)

data class Pointer(val x: Int, val y: Int, val id: Int)

data class TouchEvent(val action: Int, val actionIndex: Int, val pointers: List<Pointer>) {
    companion object {
        const val PRESS = 0
        const val RELEASE = 1
        const val DRAG = 2
        const val POINTER_DOWN = 5
        const val POINTER_UP = 6
    }
}

/**
 * Разбор и сборка сообщений Android Auto.
 *
 * Номера полей проверены по открытым реализациям головных устройств. Если
 * конкретная машина нумерует иначе, разбор не ломается: неизвестные поля
 * пропускаются, а всё сообщение целиком видно в журнале через ProtoDump.
 */
object Messages {

    // --- служебный канал -------------------------------------------------

    /** Запрос версии — не protobuf, а четыре байта: старшая и младшая версии. */
    fun parseVersion(payload: ByteArray): Pair<Int, Int> {
        if (payload.size < 4) return 1 to 1
        val major = ((payload[0].toInt() and 0xFF) shl 8) or (payload[1].toInt() and 0xFF)
        val minor = ((payload[2].toInt() and 0xFF) shl 8) or (payload[3].toInt() and 0xFF)
        return major to minor
    }

    fun versionResponse(major: Int, minor: Int, matched: Boolean): ByteArray {
        val status = if (matched) 0 else 0xFFFF
        return byteArrayOf(
            ((major shr 8) and 0xFF).toByte(), (major and 0xFF).toByte(),
            ((minor shr 8) and 0xFF).toByte(), (minor and 0xFF).toByte(),
            ((status shr 8) and 0xFF).toByte(), (status and 0xFF).toByte(),
        )
    }

    fun serviceDiscoveryRequest(deviceName: String, deviceBrand: String): ByteArray =
        ProtoWriter().string(4, deviceName).string(5, deviceBrand).toByteArray()

    fun parseDiscovery(payload: ByteArray): Discovery {
        var headUnit = HeadUnit()
        val services = ArrayList<Service>()
        val reader = ProtoReader(payload)
        while (reader.next()) {
            when (reader.field) {
                1 -> parseChannel(reader.nested())?.let { services += it }
                2 -> headUnit = headUnit.copy(name = reader.string())
                3 -> headUnit = headUnit.copy(carModel = reader.string())
                4 -> headUnit = headUnit.copy(carYear = reader.string())
                5 -> headUnit = headUnit.copy(serial = reader.string())
                6 -> headUnit = headUnit.copy(leftHandDrive = reader.bool())
                7 -> headUnit = headUnit.copy(manufacturer = reader.string())
                8 -> headUnit = headUnit.copy(model = reader.string())
                9 -> headUnit = headUnit.copy(softwareBuild = reader.string())
                10 -> headUnit = headUnit.copy(softwareVersion = reader.string())
                else -> reader.skipValue()
            }
        }
        return Discovery(headUnit, services)
    }

    private fun parseChannel(reader: ProtoReader): Service? {
        var channelId = -1
        var kind = ServiceKind.OTHER
        var audioKind = AudioKind.UNKNOWN
        val videos = ArrayList<VideoConfig>()
        val audios = ArrayList<AudioConfig>()

        while (reader.next()) {
            when (reader.field) {
                1 -> channelId = reader.int32()
                2 -> { kind = ServiceKind.SENSORS; reader.skipValue() }
                3 -> {
                    // Приёмник звука или картинки — что именно, видно по вложенным
                    // настройкам: у картинки это разрешение, у звука — частота.
                    val sink = parseMediaService(reader.nested(), videos, audios)
                    kind = if (videos.isNotEmpty()) ServiceKind.VIDEO else ServiceKind.AUDIO
                    audioKind = sink
                }
                4 -> { kind = ServiceKind.INPUT; reader.skipValue() }
                5 -> { kind = ServiceKind.MICROPHONE; parseMediaService(reader.nested(), videos, audios) }
                6 -> { kind = ServiceKind.BLUETOOTH; reader.skipValue() }
                8 -> { kind = ServiceKind.NAVIGATION; reader.skipValue() }
                else -> reader.skipValue()
            }
        }
        if (channelId < 0) return null
        return Service(channelId, kind, audioKind, videos, audios)
    }

    private fun parseMediaService(
        reader: ProtoReader,
        videos: MutableList<VideoConfig>,
        audios: MutableList<AudioConfig>,
    ): AudioKind {
        var audioKind = AudioKind.UNKNOWN
        while (reader.next()) {
            when (reader.wireType) {
                0 -> {
                    val value = reader.varint().toInt()
                    if (reader.field == 2) {
                        audioKind = AudioKind.entries.firstOrNull { it.streamType == value } ?: AudioKind.UNKNOWN
                    }
                }
                2 -> {
                    val nested = reader.bytes()
                    val config = classifyConfig(nested, videos.size + audios.size)
                    when (config) {
                        is Either.Video -> videos += config.value.copy(index = videos.size)
                        is Either.Audio -> audios += config.value.copy(index = audios.size)
                        null -> Unit
                    }
                }
                else -> reader.skipValue()
            }
        }
        return audioKind
    }

    private sealed interface Either {
        data class Video(val value: VideoConfig) : Either
        data class Audio(val value: AudioConfig) : Either
    }

    /**
     * У настроек картинки первое поле — код разрешения (маленькое число), у
     * настроек звука — частота дискретизации (16000 или 48000). Так их и
     * различаем, не полагаясь на номер поля.
     */
    private fun classifyConfig(data: ByteArray, index: Int): Either? {
        var first = -1L
        var second = 0L
        var third = 0L
        var fifth = 0L
        try {
            val reader = ProtoReader(data)
            while (reader.next()) {
                if (reader.wireType != 0) {
                    reader.skipValue()
                    continue
                }
                val value = reader.varint()
                when (reader.field) {
                    1 -> first = value
                    2 -> second = value
                    3 -> third = value
                    5 -> fifth = value
                }
            }
        } catch (e: Exception) {
            return null
        }
        if (first < 0) return null

        return if (first >= 1000) {
            Either.Audio(AudioConfig(index, first.toInt(), second.toInt().takeIf { it > 0 } ?: 16, third.toInt().takeIf { it > 0 } ?: 1))
        } else {
            val (width, height) = resolutionOf(first.toInt())
            Either.Video(VideoConfig(index, first.toInt(), width, height, frameRateOf(second.toInt()), fifth.toInt().takeIf { it > 0 } ?: 160))
        }
    }

    fun resolutionOf(code: Int): Pair<Int, Int> = when (code) {
        1 -> 800 to 480
        2 -> 1280 to 720
        3 -> 1920 to 1080
        4 -> 2560 to 1440
        5 -> 1920 to 1200
        6 -> 3840 to 2160
        7 -> 720 to 1280
        8 -> 1080 to 1920
        else -> 1280 to 720
    }

    private fun frameRateOf(code: Int): Int = if (code == 2) 60 else 30

    fun channelOpenRequest(channelId: Int, priority: Int = 0): ByteArray =
        ProtoWriter().int32(1, priority).int32(2, channelId).toByteArray()

    /** Ответы вида «получилось / не получилось»: статус в первом поле. */
    fun parseStatus(payload: ByteArray): Int {
        val reader = ProtoReader(payload)
        while (reader.next()) {
            if (reader.field == 1 && reader.wireType == 0) return reader.int32()
            reader.skipValue()
        }
        return -1
    }

    fun pingResponse(timestamp: Long): ByteArray = ProtoWriter().varint(1, timestamp).toByteArray()

    fun audioFocusResponse(state: Int): ByteArray = ProtoWriter().int32(1, state).toByteArray()

    fun audioFocusRequest(type: Int): ByteArray = ProtoWriter().int32(1, type).toByteArray()

    fun navigationFocusResponse(type: Int): ByteArray = ProtoWriter().int32(1, type).toByteArray()

    fun shutdownRequest(reason: Int = 1): ByteArray = ProtoWriter().int32(1, reason).toByteArray()

    fun shutdownResponse(): ByteArray = ByteArray(0)

    // --- канал звука и картинки -----------------------------------------

    fun avSetupRequest(configIndex: Int): ByteArray = ProtoWriter().int32(1, configIndex).toByteArray()

    data class SetupResponse(val status: Int, val maxUnacked: Int, val configIndices: List<Int>)

    fun parseSetupResponse(payload: ByteArray): SetupResponse {
        var status = -1
        var maxUnacked = 1
        val indices = ArrayList<Int>()
        val reader = ProtoReader(payload)
        while (reader.next()) {
            when (reader.field) {
                1 -> status = reader.int32()
                2 -> maxUnacked = reader.int32()
                3 -> if (reader.wireType == 0) indices += reader.int32() else reader.skipValue()
                else -> reader.skipValue()
            }
        }
        return SetupResponse(status, maxUnacked, indices)
    }

    /** focusMode: 1 — картинка нужна на экране, 2 — отдаём экран машине. */
    fun videoFocusRequest(displayIndex: Int, focusMode: Int, reason: Int = 1): ByteArray =
        ProtoWriter().int32(1, displayIndex).int32(2, focusMode).int32(3, reason).toByteArray()

    data class StartIndication(val session: Int, val config: Int)

    fun parseStartIndication(payload: ByteArray): StartIndication {
        var session = 0
        var config = 0
        val reader = ProtoReader(payload)
        while (reader.next()) {
            when (reader.field) {
                1 -> session = reader.int32()
                2 -> config = reader.int32()
                else -> reader.skipValue()
            }
        }
        return StartIndication(session, config)
    }

    /** Кусок потока: восемь байт времени в микросекундах, дальше сами данные. */
    fun mediaWithTimestamp(timestampUs: Long, data: ByteArray): ByteArray {
        val out = ByteArray(data.size + 8)
        for (i in 0 until 8) out[i] = ((timestampUs ushr (8 * (7 - i))) and 0xFF).toByte()
        System.arraycopy(data, 0, out, 8, data.size)
        return out
    }

    // --- канал ввода -----------------------------------------------------

    fun parseTouch(payload: ByteArray): TouchEvent? {
        val reader = ProtoReader(payload)
        while (reader.next()) {
            // Касания экрана приходят третьим полем, тачпада — седьмым.
            if ((reader.field == 3 || reader.field == 7) && reader.wireType == 2) {
                return parseTouchEvent(reader.nested())
            }
            reader.skipValue()
        }
        return null
    }

    private fun parseTouchEvent(reader: ProtoReader): TouchEvent {
        val pointers = ArrayList<Pointer>()
        var action = TouchEvent.PRESS
        var actionIndex = 0
        while (reader.next()) {
            when (reader.field) {
                1 -> pointers += parsePointer(reader.nested())
                2 -> actionIndex = reader.int32()
                3 -> action = reader.int32()
                else -> reader.skipValue()
            }
        }
        return TouchEvent(action, actionIndex, pointers)
    }

    private fun parsePointer(reader: ProtoReader): Pointer {
        var x = 0
        var y = 0
        var id = 0
        while (reader.next()) {
            when (reader.field) {
                1 -> x = reader.int32()
                2 -> y = reader.int32()
                3 -> id = reader.int32()
                else -> reader.skipValue()
            }
        }
        return Pointer(x, y, id)
    }

    // --- канал датчиков --------------------------------------------------

    fun sensorStartRequest(sensorType: Int, refreshIntervalUs: Long = 0): ByteArray =
        ProtoWriter().int32(1, sensorType).varint(2, refreshIntervalUs).toByteArray()

    // --- сторона головного устройства ------------------------------------
    //
    // Тем же кодом пользуется эмулятор из модуля headunit: обе стороны провода
    // собираются из одних и тех же номеров полей, так что расхождению взяться
    // неоткуда.

    fun versionRequest(major: Int = Session.PROTOCOL_MAJOR, minor: Int = Session.PROTOCOL_MINOR): ByteArray =
        byteArrayOf(
            ((major shr 8) and 0xFF).toByte(), (major and 0xFF).toByte(),
            ((minor shr 8) and 0xFF).toByte(), (minor and 0xFF).toByte(),
        )

    fun authComplete(status: Int = 0): ByteArray = ProtoWriter().int32(1, status).toByteArray()

    fun parseServiceDiscoveryRequest(payload: ByteArray): Pair<String, String> {
        var name = ""
        var brand = ""
        val reader = ProtoReader(payload)
        while (reader.next()) {
            when (reader.field) {
                4 -> name = reader.string()
                5 -> brand = reader.string()
                else -> reader.skipValue()
            }
        }
        return name to brand
    }

    fun serviceDiscoveryResponse(headUnit: HeadUnit, services: List<Service>): ByteArray {
        val writer = ProtoWriter()
        for (service in services) {
            writer.message(1) {
                int32(1, service.channelId)
                when (service.kind) {
                    ServiceKind.SENSORS -> message(2) {
                        message(1) { int32(1, Sensors.TYPE_DRIVING_STATUS) }
                        message(1) { int32(1, Sensors.TYPE_NIGHT_DATA) }
                    }
                    ServiceKind.VIDEO -> message(3) {
                        int32(1, STREAM_VIDEO)
                        for (config in service.videoConfigs) {
                            message(4) {
                                int32(1, config.resolutionCode)
                                int32(2, if (config.fps >= 60) 2 else 1)
                                int32(5, config.dpi)
                            }
                        }
                    }
                    ServiceKind.AUDIO -> message(3) {
                        int32(1, STREAM_AUDIO)
                        int32(2, service.audioKind.streamType)
                        for (config in service.audioConfigs) {
                            message(3) {
                                int32(1, config.sampleRate)
                                int32(2, config.bitDepth)
                                int32(3, config.channels)
                            }
                        }
                    }
                    ServiceKind.INPUT -> message(4) {
                        message(1) {
                            int32(1, service.videoConfigs.firstOrNull()?.width ?: 1280)
                            int32(2, service.videoConfigs.firstOrNull()?.height ?: 720)
                        }
                    }
                    else -> Unit
                }
            }
        }
        writer.string(2, headUnit.name)
        writer.string(3, headUnit.carModel)
        writer.string(4, headUnit.carYear)
        writer.string(5, headUnit.serial)
        writer.bool(6, headUnit.leftHandDrive)
        writer.string(7, headUnit.manufacturer)
        writer.string(8, headUnit.model)
        writer.string(9, headUnit.softwareBuild)
        writer.string(10, headUnit.softwareVersion)
        return writer.toByteArray()
    }

    fun parseChannelOpenRequest(payload: ByteArray): Int {
        var channelId = -1
        val reader = ProtoReader(payload)
        while (reader.next()) {
            when (reader.field) {
                2 -> channelId = reader.int32()
                else -> reader.skipValue()
            }
        }
        return channelId
    }

    fun channelOpenResponse(status: Int = 0): ByteArray = ProtoWriter().int32(1, status).toByteArray()

    fun parseSetupRequest(payload: ByteArray): Int = parseStatus(payload)

    fun setupResponse(status: Int, maxUnacked: Int, configIndices: List<Int>): ByteArray {
        val writer = ProtoWriter().int32(1, status).int32(2, maxUnacked)
        configIndices.forEach { writer.int32(3, it) }
        return writer.toByteArray()
    }

    fun parseVideoFocusRequest(payload: ByteArray): Int {
        var mode = 1
        val reader = ProtoReader(payload)
        while (reader.next()) {
            when (reader.field) {
                2 -> mode = reader.int32()
                else -> reader.skipValue()
            }
        }
        return mode
    }

    fun videoFocusIndication(mode: Int, unrequested: Boolean = false): ByteArray =
        ProtoWriter().int32(1, mode).bool(2, unrequested).toByteArray()

    fun startIndication(session: Int, config: Int): ByteArray =
        ProtoWriter().int32(1, session).int32(2, config).toByteArray()

    fun mediaAck(session: Int, value: Int = 1): ByteArray =
        ProtoWriter().int32(1, session).int32(2, value).toByteArray()

    /** Разбирает кусок потока: восемь байт времени, дальше данные. */
    fun parseMediaWithTimestamp(payload: ByteArray): Pair<Long, ByteArray> {
        if (payload.size < 8) return 0L to payload
        var timestamp = 0L
        for (i in 0 until 8) timestamp = (timestamp shl 8) or (payload[i].toLong() and 0xFF)
        return timestamp to payload.copyOfRange(8, payload.size)
    }

    fun inputEvent(timestampUs: Long, touch: TouchEvent): ByteArray =
        ProtoWriter()
            .varint(1, timestampUs)
            .message(3) {
                for (pointer in touch.pointers) {
                    message(1) {
                        int32(1, pointer.x)
                        int32(2, pointer.y)
                        int32(3, pointer.id)
                    }
                }
                int32(2, touch.actionIndex)
                int32(3, touch.action)
            }
            .toByteArray()

    fun sensorStartResponse(status: Int = 0): ByteArray = ProtoWriter().int32(1, status).toByteArray()

    /** Значения поля available_type: звук и картинка. */
    const val STREAM_AUDIO = 1
    const val STREAM_VIDEO = 3
}
