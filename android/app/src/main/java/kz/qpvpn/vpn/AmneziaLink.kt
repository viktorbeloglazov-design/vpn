package kz.qpvpn.vpn

import java.util.Base64
import java.util.zip.Inflater

/**
 * Разбор того, чем делится Amnezia.
 *
 * Кнопка «Поделиться» отдаёт ссылку `vpn://…` и QR-код с ней же. Внутри —
 * сжатый свёрток с настройками сервера, где лежит обычный текст конфигурации
 * WireGuard или AmneziaWG. Здесь ссылка разворачивается обратно в этот текст.
 *
 * Понимает и простые случаи: сам файл .conf, голый base64, несжатый JSON.
 */
object AmneziaLink {

    private const val INTERFACE_MARKER = "[Interface]"

    /** Протоколы, которыми умеет делиться Amnezia. */
    private val KNOWN_PROTOCOLS = listOf(
        "amnezia-awg" to "AmneziaWG",
        "amnezia-wireguard" to "WireGuard",
        "amnezia-openvpn" to "OpenVPN",
        "amnezia-openvpn-cloak" to "OpenVPN + Cloak",
        "amnezia-shadowsocks" to "Shadowsocks",
        "amnezia-xray" to "XRay (VLESS Reality)",
        "amnezia-ikev2" to "IKEv2",
        "amnezia-sftp" to "SFTP",
        "amnezia-tor" to "Tor",
        "amnezia-dns" to "DNS",
    )

    /**
     * Называет протокол, спрятанный в ссылке.
     *
     * Нужно, чтобы на отказ отвечать по делу: не «настройки не подошли»,
     * а «здесь OpenVPN, а программа понимает WireGuard и AmneziaWG».
     */
    fun describeProtocol(input: String): String? {
        val decoded = decodeToText(input) ?: return null
        val lower = decoded.lowercase()

        // Сначала то, что объявлено контейнером по умолчанию.
        val defaultMatch = Regex("\"defaultContainer\"\\s*:\\s*\"([a-z0-9-]+)\"").find(lower)
        defaultMatch?.groupValues?.getOrNull(1)?.let { name ->
            KNOWN_PROTOCOLS.firstOrNull { it.first == name }?.let { return it.second }
        }

        for ((key, title) in KNOWN_PROTOCOLS) {
            if (lower.contains("\"$key\"")) return title
        }
        if (lower.contains("vless://") || lower.contains("\"reality\"")) return "XRay (VLESS Reality)"
        if (lower.contains("ss://")) return "Shadowsocks"
        if (lower.contains("remote ") && lower.contains("cipher ")) return "OpenVPN"
        return null
    }

    /** Разворачивает ссылку до текста, не разбираясь, что внутри. */
    private fun decodeToText(input: String): String? {
        val text = input.trim()
        if (text.isEmpty()) return null
        if (text.contains(INTERFACE_MARKER) || text.contains("{")) return text

        val payload = text
            .removePrefix("vpn://")
            .removePrefix("VPN://")
            .removePrefix("amnezia://")
            .trim()

        val bytes = decodeBase64(payload) ?: return text
        if (bytes.size > 4) {
            inflate(bytes.copyOfRange(4, bytes.size))?.let { return it }
        }
        inflate(bytes)?.let { return it }
        return String(bytes, Charsets.UTF_8)
    }

    /** Достаёт текст конфигурации из чего угодно, чем поделились. */
    fun extractConfig(input: String): String? {
        val text = input.trim()
        if (text.isEmpty()) return null

        // Уже готовый файл настроек.
        if (text.contains(INTERFACE_MARKER)) {
            return cleanUp(text)
        }

        val payload = text
            .removePrefix("vpn://")
            .removePrefix("VPN://")
            .removePrefix("amnezia://")
            .trim()

        decodeBase64(payload)?.let { bytes ->
            fromBytes(bytes)?.let { return it }
        }

        // Бывает, что ссылку присылают уже раскодированной.
        return fromText(text)
    }

    private fun fromBytes(bytes: ByteArray): String? {
        // Qt кладёт впереди четыре байта с исходным размером, дальше zlib.
        if (bytes.size > 4) {
            inflate(bytes.copyOfRange(4, bytes.size))?.let { unpacked ->
                fromText(unpacked)?.let { return it }
            }
        }
        inflate(bytes)?.let { unpacked ->
            fromText(unpacked)?.let { return it }
        }
        return fromText(String(bytes, Charsets.UTF_8))
    }

    /**
     * В свёртке Amnezia настройки лежат в поле вложенного JSON, и структура
     * от версии к версии меняется. Поэтому ищем не по именам полей, а по
     * самому признаку конфигурации — строке «[Interface]».
     */
    private fun fromText(text: String): String? {
        if (!text.contains(INTERFACE_MARKER)) return null
        if (!text.contains("\"")) return cleanUp(text)

        // Текст внутри JSON приходит с экранированными переводами строк.
        val start = text.indexOf(INTERFACE_MARKER)
        val quoteBefore = text.lastIndexOf('"', start)
        if (quoteBefore < 0) return cleanUp(text)

        val quoteAfter = findClosingQuote(text, start)
        if (quoteAfter < 0) return cleanUp(text)

        val raw = text.substring(quoteBefore + 1, quoteAfter)
        return cleanUp(unescapeJson(raw))
    }

    private fun findClosingQuote(text: String, from: Int): Int {
        var index = from
        while (index < text.length) {
            if (text[index] == '"' && text.getOrNull(index - 1) != '\\') return index
            index++
        }
        return -1
    }

    private fun unescapeJson(value: String): String = value
        .replace("\\r\\n", "\n")
        .replace("\\n", "\n")
        .replace("\\r", "\n")
        .replace("\\t", "\t")
        .replace("\\\"", "\"")
        .replace("\\\\", "\\")

    /** Обрезает всё, что оказалось до и после самой конфигурации. */
    private fun cleanUp(text: String): String {
        val start = text.indexOf(INTERFACE_MARKER)
        if (start < 0) return text.trim()
        val body = text.substring(start)
        val lines = body.lines().takeWhile { line ->
            val trimmed = line.trim()
            trimmed.isEmpty() ||
                trimmed.startsWith("[") ||
                trimmed.startsWith("#") ||
                trimmed.contains("=")
        }
        return lines.joinToString("\n").trim()
    }

    private fun decodeBase64(value: String): ByteArray? {
        val normalized = value
            .replace('-', '+')
            .replace('_', '/')
            .filterNot { it == '\n' || it == '\r' || it == ' ' }
        val padded = when (normalized.length % 4) {
            2 -> "$normalized=="
            3 -> "$normalized="
            0 -> normalized
            else -> return null
        }
        return try {
            Base64.getDecoder().decode(padded)
        } catch (error: IllegalArgumentException) {
            null
        }
    }

    private fun inflate(data: ByteArray): String? {
        for (raw in listOf(false, true)) {
            try {
                val inflater = Inflater(raw)
                inflater.setInput(data)
                val buffer = ByteArray(16 * 1024)
                val output = StringBuilder()
                var guard = 0
                while (!inflater.finished() && guard < 2_000) {
                    val size = inflater.inflate(buffer)
                    if (size == 0 && (inflater.needsInput() || inflater.needsDictionary())) break
                    output.append(String(buffer, 0, size, Charsets.UTF_8))
                    guard++
                }
                inflater.end()
                if (output.isNotEmpty()) return output.toString()
            } catch (error: Exception) {
                // Пробуем следующий способ распаковки.
            }
        }
        return null
    }
}
