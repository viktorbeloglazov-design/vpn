package kz.carlink.headunit

import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem
import javax.sound.sampled.SourceDataLine

/** Динамики «машины»: то, что играет телефон, слышно на компьютере. */
class Speaker(private val log: (String) -> Unit) {

    private var line: SourceDataLine? = null

    fun start(sampleRate: Int, bitDepth: Int, channels: Int) {
        stop()
        val format = AudioFormat(sampleRate.toFloat(), bitDepth, channels, true, false)
        line = try {
            (AudioSystem.getLine(javax.sound.sampled.DataLine.Info(SourceDataLine::class.java, format)) as SourceDataLine)
                .apply {
                    open(format)
                    start()
                }
        } catch (e: Exception) {
            log("звук не открылся: ${e.message}")
            null
        }
    }

    fun play(data: ByteArray) {
        line?.write(data, 0, data.size)
    }

    fun stop() {
        line?.let {
            runCatching { it.drain() }
            runCatching { it.close() }
        }
        line = null
    }
}
