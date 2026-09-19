package kz.qpvpn.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.InetAddress
import java.net.URL

/**
 * Превращает домены в адреса, по которым строятся маршруты.
 *
 * Сложность в том, что внутри России ответы обычного DNS для заблокированных
 * сайтов часто подменены. Поэтому сначала спрашиваем публичные серверы по
 * защищённому каналу (DNS поверх HTTPS), и только если не вышло — системный
 * резолвер.
 */
object DomainResolver {

    private const val PARALLEL = 16
    private const val TIMEOUT_MS = 4_000

    private val dohEndpoints = listOf(
        "https://dns.google/resolve",
        "https://cloudflare-dns.com/dns-query",
    )

    /** Кэш на время работы: между переподключениями адреса обычно не меняются. */
    private val cache = HashMap<String, List<Ipv4Net>>()

    /** Резолвит сразу много доменов, не выстраивая их в очередь по одному. */
    suspend fun resolveAll(hosts: List<String>, useSecureDns: Boolean = true): List<Ipv4Net> =
        coroutineScope {
            val gate = Semaphore(PARALLEL)
            val results = hosts.distinct().map { host ->
                async(Dispatchers.IO) {
                    gate.withPermit { resolveWithWww(host, useSecureDns) }
                }
            }.awaitAll()
            results.flatten().distinct()
        }

    suspend fun resolveWithWww(host: String, useSecureDns: Boolean = true): List<Ipv4Net> {
        val direct = resolve(host, useSecureDns)
        if (host.startsWith("www.") || host.count { it == '.' } != 1) return direct
        return (direct + resolve("www.$host", useSecureDns)).distinct()
    }

    suspend fun resolve(host: String, useSecureDns: Boolean = true): List<Ipv4Net> {
        synchronized(cache) { cache[host] }?.let { return it }

        val secure = if (useSecureDns) resolveOverHttps(host) else emptyList()
        val result = secure.ifEmpty { resolveWithSystem(host) }

        if (result.isNotEmpty()) {
            synchronized(cache) { cache[host] = result }
        }
        return result
    }

    fun clearCache() {
        synchronized(cache) { cache.clear() }
    }

    // MARK: - Способы

    private fun resolveWithSystem(host: String): List<Ipv4Net> = try {
        InetAddress.getAllByName(host)
            .asSequence()
            .filterIsInstance<Inet4Address>()
            .filter { !it.isLoopbackAddress && !it.isLinkLocalAddress && !it.isAnyLocalAddress }
            .mapNotNull { Cidr.parse(it.hostAddress ?: "") }
            .distinct()
            .toList()
    } catch (error: Exception) {
        emptyList()
    }

    private suspend fun resolveOverHttps(host: String): List<Ipv4Net> = withContext(Dispatchers.IO) {
        for (endpoint in dohEndpoints) {
            val answers = query(endpoint, host)
            if (answers.isNotEmpty()) return@withContext answers
        }
        emptyList()
    }

    private fun query(endpoint: String, host: String): List<Ipv4Net> {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL("$endpoint?name=$host&type=A").openConnection() as HttpURLConnection).apply {
                connectTimeout = TIMEOUT_MS
                readTimeout = TIMEOUT_MS
                requestMethod = "GET"
                setRequestProperty("Accept", "application/dns-json")
            }
            if (connection.responseCode != 200) return emptyList()

            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val answers = JSONObject(body).optJSONArray("Answer") ?: return emptyList()

            (0 until answers.length())
                .mapNotNull { index -> answers.optJSONObject(index) }
                .filter { it.optInt("type") == 1 }            // A-запись
                .mapNotNull { Cidr.parse(it.optString("data")) }
                .distinct()
        } catch (error: Exception) {
            emptyList()
        } finally {
            connection?.disconnect()
        }
    }
}
