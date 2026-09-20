package kz.qpvpn.net

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.max

/**
 * Замер скорости — через туннель и мимо него, на одном и том же файле.
 *
 * Без двух чисел разговор о скорости бессмысленный: в кафе Wi-Fi бывает
 * медленнее любого VPN, и тогда виноват не туннель. Одна и та же закачка,
 * снятая двумя путями, отвечает на вопрос сразу.
 */
object SpeedTest {

    /** Сколько качаем и сколько на это отводим. */
    private const val BYTES = 25_000_000
    private const val SECONDS = 8

    private val downUrl = "https://speed.cloudflare.com/__down?bytes=$BYTES"
    private const val UP_URL = "https://speed.cloudflare.com/__up"

    data class Result(
        /** Мегабит в секунду через туннель, 0 — не получилось. */
        val throughTunnel: Double,
        /** Мегабит в секунду мимо туннеля, 0 — не получилось. */
        val direct: Double,
        /** Отдача через туннель и мимо него. */
        val uploadThroughTunnel: Double = 0.0,
        val uploadDirect: Double = 0.0,
        val note: String = "",
    ) {
        val hasAny: Boolean get() = throughTunnel > 0 || direct > 0

        /** Мешает ли VPN: сравниваем, только если оба замера удались. */
        val tunnelIsSlower: Boolean
            get() = throughTunnel > 0 && direct > 0 && direct > throughTunnel * 1.5

        val uploadIsSlower: Boolean
            get() = uploadThroughTunnel > 0 && uploadDirect > 0 &&
                uploadDirect > uploadThroughTunnel * 1.5
    }

    suspend fun measure(context: Context): Result = withContext(Dispatchers.IO) {
        val bypass = underlyingNetwork(context)

        val tunnel = download(network = null)
        val direct = if (bypass != null) download(network = bypass) else 0.0
        val upTunnel = upload(network = null)
        val upDirect = if (bypass != null) upload(network = bypass) else 0.0

        val note = when {
            tunnel <= 0 && direct <= 0 -> "Не удалось скачать пробный файл — сеть не отвечает."
            direct <= 0 -> "Замерить без VPN не вышло: обычно это значит, что сеть сама его не пускает."
            tunnel <= 0 -> "Через VPN скачать не удалось — похоже, туннель не работает."
            else -> ""
        }
        Result(
            throughTunnel = tunnel,
            direct = direct,
            uploadThroughTunnel = upTunnel,
            uploadDirect = upDirect,
            note = note,
        )
    }

    /** Отдача: шлём поток нулей столько же секунд и считаем, сколько ушло. */
    private fun upload(network: Network?): Double {
        val deadline = System.currentTimeMillis() + SECONDS * 1_000L
        var total = 0L
        val started = System.nanoTime()

        return try {
            val connection = (network?.openConnection(URL(UP_URL)) ?: URL(UP_URL).openConnection())
                as HttpURLConnection
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.connectTimeout = 8_000
            connection.readTimeout = 8_000
            connection.useCaches = false
            connection.setChunkedStreamingMode(64 * 1024)

            val buffer = ByteArray(64 * 1024)
            connection.outputStream.use { stream ->
                while (System.currentTimeMillis() < deadline && total < BYTES) {
                    stream.write(buffer)
                    total += buffer.size
                }
                stream.flush()
            }
            connection.responseCode
            connection.disconnect()

            val seconds = (System.nanoTime() - started) / 1_000_000_000.0
            if (total <= 0 || seconds <= 0) 0.0 else total * 8.0 / seconds / 1_000_000.0
        } catch (error: Exception) {
            0.0
        }
    }

    /** Мегабиты в секунду. 0 — не получилось. */
    private fun download(network: Network?): Double {
        val deadline = System.currentTimeMillis() + SECONDS * 1_000L
        var total = 0L
        val started = System.nanoTime()

        return try {
            val connection = (network?.openConnection(URL(downUrl)) ?: URL(downUrl).openConnection())
                as HttpURLConnection
            connection.connectTimeout = 8_000
            connection.readTimeout = 8_000
            connection.useCaches = false

            connection.inputStream.use { stream ->
                val buffer = ByteArray(64 * 1024)
                while (System.currentTimeMillis() < deadline) {
                    val read = stream.read(buffer)
                    if (read <= 0) break
                    total += read
                }
            }
            connection.disconnect()

            val seconds = (System.nanoTime() - started) / 1_000_000_000.0
            if (total <= 0 || seconds <= 0) 0.0 else total * 8.0 / seconds / 1_000_000.0
        } catch (error: Exception) {
            0.0
        }
    }

    /**
     * Настоящая сеть телефона — Wi-Fi или мобильная, не туннель.
     *
     * Сокет, привязанный к ней, уходит мимо VPN: так и получается второй
     * замер, с которым есть что сравнивать.
     */
    private fun underlyingNetwork(context: Context): Network? {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return null
        return manager.allNetworks.firstOrNull { network ->
            val capabilities = manager.getNetworkCapabilities(network) ?: return@firstOrNull false
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        }
    }

    /** «12.3 Мбит/с» — в таком виде число понятно без пояснений. */
    fun format(mbits: Double): String = when {
        mbits <= 0 -> "—"
        mbits >= 100 -> "${mbits.toInt()} Мбит/с"
        else -> String.format("%.1f Мбит/с", max(mbits, 0.1))
    }
}
