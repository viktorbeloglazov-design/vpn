package kz.qpvpn.vpn

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL

/**
 * Отвечает ли сервер X-Ray.
 *
 * У прежнего протокола было рукопожатие, и по его времени было видно,
 * жив ли сервер. У X-Ray рукопожатия нет, поэтому проверяем делом:
 * маленькая страница, которая отдаёт «204», запрашивается через
 * socks-вход xray — то есть через сервер.
 */
object XrayProbe {

    private val urls = listOf(
        "https://www.gstatic.com/generate_204",
        "https://cp.cloudflare.com/generate_204",
    )

    suspend fun answers(): Boolean = withContext(Dispatchers.IO) {
        val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", XrayLink.SOCKS_PORT))
        urls.any { address ->
            runCatching {
                val connection = URL(address).openConnection(proxy) as HttpURLConnection
                connection.connectTimeout = 8_000
                connection.readTimeout = 8_000
                connection.instanceFollowRedirects = false
                try {
                    connection.responseCode in setOf(200, 204)
                } finally {
                    connection.disconnect()
                }
            }.getOrDefault(false)
        }
    }
}
