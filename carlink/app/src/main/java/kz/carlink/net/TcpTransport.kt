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

        internal fun of(socket: Socket): TcpTransport = TcpTransport(socket)
    }
}

/**
 * Ожидание подключения на телефоне.
 *
 * Так работает беспроводной Android Auto: телефон держит открытый порт, а
 * головное устройство подключается к нему само. Стенд на компьютере умеет то же
 * самое ключом `--connect`.
 */
class TcpListener(port: Int) {

    private val server = java.net.ServerSocket(port)

    val localPort: Int get() = server.localPort

    /** Блокируется, пока кто-нибудь не подключится. [close] прерывает ожидание. */
    fun accept(): TcpTransport {
        val socket = server.accept()
        socket.tcpNoDelay = true
        return TcpTransport.of(socket)
    }

    fun close() {
        runCatching { server.close() }
    }
}

/** Адреса телефона в сети — их показываем, чтобы было что вбить в машине. */
object LocalAddresses {

    fun list(): List<String> = try {
        java.net.NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.isUp && !it.isLoopback }
            .flatMap { iface -> iface.inetAddresses.toList().map { iface.name to it } }
            .filter { (_, address) -> address is java.net.Inet4Address }
            .map { (name, address) -> "$name ${address.hostAddress}" }
    } catch (e: Exception) {
        emptyList()
    }
}
