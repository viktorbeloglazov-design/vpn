package kz.carlink.headunit

import java.awt.image.BufferedImage
import java.awt.image.DataBufferByte
import java.io.IOException

/**
 * Показ картинки через ffmpeg.
 *
 * Декодировать H.264 самой Java нечем, зато ffmpeg стоит почти везде: поток
 * уходит ему на вход, обратно приходят готовые кадры в BGR, которые остаётся
 * положить в окно. Нет ffmpeg — стенд работает дальше, просто без картинки:
 * протокол, касания и звук от этого не зависят.
 */
class Ffmpeg(
    private val width: Int,
    private val height: Int,
    private val log: (String) -> Unit,
) {
    private var process: Process? = null

    @Volatile
    private var alive = false

    fun start(onImage: (BufferedImage) -> Unit): Boolean {
        val command = listOf(
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-fflags", "nobuffer", "-flags", "low_delay",
            "-f", "h264", "-i", "pipe:0",
            "-f", "rawvideo", "-pix_fmt", "bgr24", "pipe:1",
        )
        val started = try {
            ProcessBuilder(command).redirectError(ProcessBuilder.Redirect.DISCARD).start()
        } catch (e: IOException) {
            log("ffmpeg не найден — картинки не будет, остальное работает")
            return false
        }
        process = started
        alive = true

        Thread({
            val frameSize = width * height * 3
            val buffer = ByteArray(frameSize)
            val input = started.inputStream
            while (alive) {
                var read = 0
                while (read < frameSize) {
                    val n = try {
                        input.read(buffer, read, frameSize - read)
                    } catch (e: IOException) {
                        -1
                    }
                    if (n < 0) {
                        alive = false
                        return@Thread
                    }
                    read += n
                }
                val image = BufferedImage(width, height, BufferedImage.TYPE_3BYTE_BGR)
                val pixels = (image.raster.dataBuffer as DataBufferByte).data
                System.arraycopy(buffer, 0, pixels, 0, frameSize)
                onImage(image)
            }
        }, "carlink-decode").apply { isDaemon = true }.start()

        log("картинку декодирует ffmpeg")
        return true
    }

    fun feed(data: ByteArray) {
        val target = process ?: return
        if (!alive) return
        try {
            target.outputStream.write(data)
            target.outputStream.flush()
        } catch (e: IOException) {
            alive = false
            log("ffmpeg закрылся, картинки больше не будет")
        }
    }

    fun stop() {
        alive = false
        process?.destroy()
        process = null
    }
}
