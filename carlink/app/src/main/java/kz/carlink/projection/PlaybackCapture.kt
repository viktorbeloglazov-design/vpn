package kz.carlink.projection

import android.annotation.SuppressLint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import kz.carlink.aa.AudioConfig
import kz.carlink.aa.AudioSource
import kz.carlink.aa.FrameSink

/**
 * Забирает звук, который играет телефон, и отдаёт его в динамики машины.
 *
 * Работает через тот же разрешённый пользователем захват экрана: система
 * позволяет слушать чужое воспроизведение, если программа не запретила это
 * явно (запрещают обычно только видеосервисы с защищённым содержимым).
 */
class PlaybackCapture(
    private val mediaProjection: () -> MediaProjection?,
    private val log: (String) -> Unit,
) : AudioSource {

    private var record: AudioRecord? = null
    private var thread: Thread? = null

    @Volatile
    private var running = false

    @SuppressLint("MissingPermission")
    override fun start(config: AudioConfig, sink: FrameSink) {
        val projection = mediaProjection()
        if (projection == null) {
            log("звук не отдаю: нет разрешения на захват")
            return
        }
        val channelMask = if (config.channels >= 2) AudioFormat.CHANNEL_IN_STEREO else AudioFormat.CHANNEL_IN_MONO
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(config.sampleRate)
            .setChannelMask(channelMask)
            .build()

        val capture = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val minBuffer = AudioRecord.getMinBufferSize(config.sampleRate, channelMask, AudioFormat.ENCODING_PCM_16BIT)
        val bufferSize = maxOf(minBuffer, CHUNK_BYTES * 4)

        val recorder = try {
            AudioRecord.Builder()
                .setAudioFormat(format)
                .setBufferSizeInBytes(bufferSize)
                .setAudioPlaybackCaptureConfig(capture)
                .build()
        } catch (e: Exception) {
            log("не смог открыть захват звука: ${e.message}")
            return
        }

        record = recorder
        running = true
        recorder.startRecording()
        log("отдаю звук: ${config.sampleRate} Гц, ${config.channels} кан.")

        thread = Thread({
            val buffer = ByteArray(CHUNK_BYTES)
            while (running) {
                val read = recorder.read(buffer, 0, buffer.size)
                if (read <= 0) continue
                sink.onFrame(buffer.copyOf(read), System.nanoTime() / 1000)
            }
        }, "carlink-audio").also { it.start() }
    }

    override fun stop() {
        running = false
        thread?.join(300)
        thread = null
        runCatching { record?.stop() }
        runCatching { record?.release() }
        record = null
    }

    companion object {
        /** Кусок примерно на 20 мс стереозвука 48 кГц. */
        private const val CHUNK_BYTES = 4096
    }
}
