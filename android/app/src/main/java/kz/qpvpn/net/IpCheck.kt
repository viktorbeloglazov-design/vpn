package kz.qpvpn.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

data class IpInfo(val ip: String, val country: String, val city: String) {
    val isKazakhstan: Boolean get() = country.equals("KZ", ignoreCase = true)

    val summary: String
        get() = buildString {
            append(ip)
            if (country.isNotEmpty()) {
                append(" · ")
                append(if (isKazakhstan) "🇰🇿 KZ" else country.uppercase())
                if (city.isNotEmpty()) append(", $city")
            }
        }
}

/**
 * Проверка внешнего адреса — так видно, из какой страны вас видят сайты.
 *
 * Источников несколько: любой из них может быть недоступен — и сам по себе,
 * и потому, что его закрыли в конкретной сети. Опрашиваем по очереди, пока
 * кто-нибудь не ответит.
 */
object IpCheck {

    private data class Source(
        val url: String,
        val read: (JSONObject) -> IpInfo,
    )

    private val sources = listOf(
        Source("https://ipinfo.io/json") { json ->
            IpInfo(json.optString("ip"), json.optString("country"), json.optString("city"))
        },
        Source("https://ipapi.co/json/") { json ->
            IpInfo(json.optString("ip"), json.optString("country_code"), json.optString("city"))
        },
        Source("https://api.ip.sb/geoip") { json ->
            IpInfo(json.optString("ip"), json.optString("country_code"), json.optString("city"))
        },
        Source("https://api.ipify.org?format=json") { json ->
            IpInfo(json.optString("ip"), "", "")
        },
    )

    suspend fun fetch(): Result<IpInfo> = withContext(Dispatchers.IO) {
        var last: Exception? = null

        for (source in sources) {
            var connection: HttpURLConnection? = null
            try {
                connection = (URL(source.url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 7_000
                    readTimeout = 7_000
                    requestMethod = "GET"
                    setRequestProperty("Accept", "application/json")
                    setRequestProperty("User-Agent", "QPVPN")
                }
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                val info = source.read(JSONObject(body))
                if (info.ip.isNotEmpty()) return@withContext Result.success(info)
            } catch (error: Exception) {
                last = error
            } finally {
                connection?.disconnect()
            }
        }

        Result.failure(last ?: Exception("ни один сервис проверки не ответил"))
    }
}
