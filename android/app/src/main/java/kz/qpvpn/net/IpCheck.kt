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

/** Проверка внешнего адреса — так видно, из какой страны вас видят сайты. */
object IpCheck {

    suspend fun fetch(): Result<IpInfo> = withContext(Dispatchers.IO) {
        var connection: HttpURLConnection? = null
        try {
            connection = (URL("https://ipinfo.io/json").openConnection() as HttpURLConnection).apply {
                connectTimeout = 10_000
                readTimeout = 10_000
                requestMethod = "GET"
                setRequestProperty("Accept", "application/json")
            }
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            Result.success(
                IpInfo(
                    ip = json.optString("ip"),
                    country = json.optString("country"),
                    city = json.optString("city"),
                )
            )
        } catch (error: Exception) {
            Result.failure(error)
        } finally {
            connection?.disconnect()
        }
    }
}
