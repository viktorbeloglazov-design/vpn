package kz.carlink.headunit

import kz.carlink.aa.AudioConfig
import kz.carlink.aa.FrameCodec
import kz.carlink.aa.VideoConfig
import java.awt.GraphicsEnvironment
import java.io.File
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicReference

/**
 * Стенд головного устройства.
 *
 * Запускается на компьютере и ждёт телефон. Телефон подключается по сети —
 * проще всего прокинуть порт по тому же кабелю USB:
 *
 *     adb reverse tcp:5288 tcp:5288
 *
 * После этого в приложении на телефоне выбирается «Стенд на компьютере», и вся
 * проекция — рукопожатие, список каналов, картинка, звук и касания — работает
 * без машины.
 */
fun main(args: Array<String>) {
    val options = Options.parse(args)
    val profile = CarProfile.taycan(options.width, options.height, options.fps)

    println("CarLink — стенд головного устройства")
    println("  экран машины: ${options.width}×${options.height}, ${options.fps} к/с")
    if (options.connect == null) {
        println("  жду телефон на порту ${options.port}")
        println()
        println("  на компьютере:  adb reverse tcp:${options.port} tcp:${options.port}")
        println("  на телефоне:    режим «Стенд», адрес 127.0.0.1:${options.port}")
    } else {
        println("  подключаюсь к телефону ${options.connect}")
        println()
        println("  на телефоне:    режим «Ждать по Wi-Fi»")
    }
    println()

    val current = AtomicReference<HeadUnit?>(null)
    val window = if (options.window && !GraphicsEnvironment.isHeadless()) {
        VideoWindow(options.width, options.height) { touch -> current.get()?.sendTouch(touch) }.also { it.open() }
    } else {
        null
    }

    val target = options.connect
    if (target != null) {
        // Телефон ждёт подключения сам — так же ведёт себя беспроводной
        // Android Auto: машина стучится к телефону, а не наоборот.
        val parts = target.split(":")
        val host = parts[0]
        val port = parts.getOrNull(1)?.toIntOrNull() ?: options.port
        while (true) {
            window?.status("подключаюсь к $host:$port")
            val socket = try {
                Socket().apply {
                    tcpNoDelay = true
                    connect(InetSocketAddress(host, port), 4000)
                }
            } catch (e: Exception) {
                println("телефон не отвечает ($host:$port): ${e.message}, пробую ещё раз через 3 с")
                Thread.sleep(3000)
                continue
            }
            println("подключился к телефону $host:$port")
            serve(socket, profile, options, window, current)
        }
    }

    ServerSocket(options.port).use { server ->
        while (true) {
            window?.status("жду телефон на порту ${options.port}")
            val socket = server.accept()
            socket.tcpNoDelay = true
            println("телефон подключился: ${socket.inetAddress.hostAddress}")
            serve(socket, profile, options, window, current)
        }
    }
}

private fun serve(
    socket: Socket,
    profile: CarProfile,
    options: Options,
    window: VideoWindow?,
    current: AtomicReference<HeadUnit?>,
) {
    val decoder = Ffmpeg(options.width, options.height, ::log)
    val speaker = Speaker(::log)
    val recorder = options.record?.let { FileOutputStream(File(it)) }
    var decoding = false

    val events = object : HeadUnitEvents {
        override fun log(line: String) {
            kz.carlink.headunit.log(line)
            window?.status(line)
        }

        override fun onPhone(name: String, brand: String) {
            window?.status("подключён $brand $name")
        }

        override fun onVideoStart(config: VideoConfig) {
            if (window != null && !decoding) {
                decoding = decoder.start { image -> window.show(image) }
                if (!decoding) window.hint("ffmpeg не найден: картинки нет, касания и звук работают")
            }
        }

        override fun onVideoFrame(data: ByteArray, timestampUs: Long) {
            if (decoding) decoder.feed(data)
            recorder?.write(data)
        }

        override fun onAudioStart(config: AudioConfig) {
            speaker.start(config.sampleRate, config.bitDepth, config.channels)
        }

        override fun onAudioFrame(data: ByteArray) = speaker.play(data)

        override fun onClosed() {
            decoder.stop()
            speaker.stop()
            runCatching { recorder?.close() }
        }
    }

    val headUnit = HeadUnit(FrameCodec(socket.getInputStream(), socket.getOutputStream()), profile, events)
    current.set(headUnit)
    try {
        headUnit.run()
    } finally {
        current.set(null)
        runCatching { socket.close() }
        println("телефон отключился")
    }
}

private val clock = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault())

internal fun log(line: String) = println("${clock.format(Date())}  $line")

/** Настройки запуска. */
data class Options(
    val port: Int = 5288,
    val width: Int = 1280,
    val height: Int = 720,
    val fps: Int = 30,
    val window: Boolean = true,
    val record: String? = null,
    /** Адрес телефона, если подключаться должен стенд, а не телефон. */
    val connect: String? = null,
) {
    companion object {
        fun parse(args: Array<String>): Options {
            var options = Options()
            var index = 0
            while (index < args.size) {
                val key = args[index]
                val value = args.getOrNull(index + 1)
                when (key) {
                    "--port" -> options = options.copy(port = value!!.toInt())
                    "--fps" -> options = options.copy(fps = value!!.toInt())
                    "--record" -> options = options.copy(record = value!!)
                    "--connect" -> options = options.copy(connect = value!!)
                    "--size" -> {
                        val parts = value!!.split("x", "×")
                        options = options.copy(width = parts[0].toInt(), height = parts[1].toInt())
                    }
                    "--no-window" -> {
                        options = options.copy(window = false)
                        index--
                    }
                    "--help", "-h" -> {
                        println(
                            "--port 5288  --size 1280x720  --fps 30  --record поток.h264  " +
                                "--no-window  --connect адрес-телефона:5288"
                        )
                        kotlin.system.exitProcess(0)
                    }
                    else -> {
                        println("не знаю ключ $key")
                        kotlin.system.exitProcess(1)
                    }
                }
                index += 2
            }
            return options
        }
    }
}
