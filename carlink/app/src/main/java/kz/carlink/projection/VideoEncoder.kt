package kz.carlink.projection

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.view.Surface
import kz.carlink.aa.FrameSink
import java.nio.ByteBuffer

/**
 * Кодировщик картинки в H.264 — его и ждёт машина.
 *
 * Кадры берутся прямо с поверхности (Surface), которую отдаём виртуальному
 * экрану: пиксели не ходят через процессор, поэтому телефон не греется.
 * Первым в поток уходит блок настроек кодека (SPS/PPS) — без него машина
 * покажет чёрный экран.
 */
class VideoEncoder(
    private val width: Int,
    private val height: Int,
    private val fps: Int,
    private val log: (String) -> Unit,
) {
    private var codec: MediaCodec? = null
    private var thread: Thread? = null

    @Volatile
    private var running = false

    /** Поверхность, на которую надо рисовать. Есть только между start и stop. */
    var surface: Surface? = null
        private set

    fun start(sink: FrameSink) {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrateFor(width, height, fps))
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            // Опорный кадр раз в секунду: если машина подключилась в середине
            // потока, картинка появится быстро.
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
            setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel31)
            setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
        }

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        surface = encoder.createInputSurface()
        encoder.start()
        codec = encoder
        running = true

        thread = Thread({ drain(encoder, sink) }, "carlink-video").apply {
            priority = Thread.NORM_PRIORITY + 1
            start()
        }
        log("кодировщик запущен: ${width}×${height}, $fps к/с")
    }

    private fun drain(encoder: MediaCodec, sink: FrameSink) {
        val info = MediaCodec.BufferInfo()
        while (running) {
            try {
                val index = encoder.dequeueOutputBuffer(info, 50_000)
                if (index < 0) continue
                val buffer: ByteBuffer? = encoder.getOutputBuffer(index)
                if (buffer != null && info.size > 0) {
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    val data = ByteArray(info.size)
                    buffer.get(data)
                    sink.onFrame(data, info.presentationTimeUs)
                }
                encoder.releaseOutputBuffer(index, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            } catch (e: IllegalStateException) {
                if (running) log("кодировщик остановился: ${e.message}")
                break
            }
        }
    }

    /** Просит кодировщик выдать опорный кадр — например, когда машина «моргнула». */
    fun requestKeyFrame() {
        val params = android.os.Bundle()
        params.putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
        runCatching { codec?.setParameters(params) }
    }

    fun stop() {
        running = false
        thread?.join(500)
        thread = null
        runCatching { codec?.stop() }
        runCatching { codec?.release() }
        codec = null
        runCatching { surface?.release() }
        surface = null
    }

    private fun bitrateFor(width: Int, height: Int, fps: Int): Int {
        // Примерно 0,1 бита на пиксель в кадре — картинка чистая, а провод USB
        // такой поток тянет с запасом.
        val estimate = (width.toLong() * height * fps * 0.1).toLong()
        return estimate.coerceIn(2_000_000L, 12_000_000L).toInt()
    }
}
