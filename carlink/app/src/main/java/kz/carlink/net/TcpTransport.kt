package kz.carlink.net

import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Связь со стендом на компьютере.
 *
 * Тот же протокол, что и по проводу, только вместо режима аксессуара —
 * обычное соединение TCP. Удобнее всего пробросить порт по кабелю отладки:
 *
 *     adb reverse tcp:5288 tcp:5288
 *
 * тогда телефон стучится на 127.0.0.1, и никакой общей сети не нужно.
 */
class TcpTransport private constructor(private val socket: Socket) {

    val input: InputStream = socket.getInputStream()
    val output: OutputStream = socket.getOutputStream()

    fun close() {
        runCatching { socket.close() }
    }

    companion object {
        fun open(host: String, port: Int, timeoutMs: Int = 4000): TcpTransport {
            val socket = Socket()
            socket.tcpNoDelay = true
            socket.connect(InetSocketAddress(host, port), timeoutMs)
            return TcpTransport(socket)
        }
    }
}
