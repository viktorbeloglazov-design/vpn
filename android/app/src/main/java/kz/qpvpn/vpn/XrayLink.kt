package kz.qpvpn.vpn

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.net.URLDecoder
import java.util.Base64

/**
 * Ключ X-Ray: ссылка vless://, vmess://, trojan:// или ss://.
 *
 * Сервер теперь работает на X-Ray. Ключ — одна строка: адрес сервера,
 * идентификатор и способ маскировки (Reality, TLS, вебсокет). Разбор
 * тот же, что на Mac, — чтобы один ключ одинаково понимали оба
 * приложения.
 */
data class XrayLink(
    val kind: Kind,
    val host: String,
    val port: Int,
    /** UUID для VLESS и VMess, пароль для Trojan и Shadowsocks. */
    val secret: String,
    val method: String = "",
    val flow: String = "",
    val network: String = "tcp",
    val security: String = "none",
    val sni: String = "",
    val fingerprint: String = "",
    val alpn: List<String> = emptyList(),
    val publicKey: String = "",
    val shortId: String = "",
    val spiderX: String = "",
    val path: String = "",
    val hostHeader: String = "",
    val serviceName: String = "",
    val mode: String = "",
    val headerType: String = "",
    val allowInsecure: Boolean = false,
    val name: String = "",
) {
    enum class Kind { VLESS, VMESS, TROJAN, SHADOWSOCKS }

    class ParseException(message: String) : IllegalArgumentException(message)

    val endpoint: String get() = if (host.contains(':')) "[$host]:$port" else "$host:$port"

    val title: String
        get() {
            val base = when (kind) {
                Kind.VLESS -> "VLESS"
                Kind.VMESS -> "VMess"
                Kind.TROJAN -> "Trojan"
                Kind.SHADOWSOCKS -> "Shadowsocks"
            }
            return when (security) {
                "reality" -> "X-Ray ($base Reality)"
                "tls" -> "X-Ray ($base TLS)"
                else -> "X-Ray ($base)"
            }
        }

    /** Тот же ключ, но к другому входу — для запасного узла. */
    fun withEndpoint(endpoint: String): XrayLink {
        val (newHost, newPort) = splitHostPort(endpoint) ?: return this
        return copy(host = newHost, port = newPort)
    }

    /** Настройки xray: socks-вход только для самого телефона и выход на сервер. */
    fun toConfigJson(socksPort: Int = SOCKS_PORT): String {
        val config = buildJsonObject {
            putJsonObject("log") { put("loglevel", "warning") }
            putJsonArray("inbounds") {
                add(buildJsonObject {
                    put("tag", "socks")
                    put("listen", "127.0.0.1")
                    put("port", socksPort)
                    put("protocol", "socks")
                    putJsonObject("settings") {
                        put("auth", "noauth")
                        put("udp", true)
                        put("ip", "127.0.0.1")
                    }
                })
            }
            putJsonArray("outbounds") {
                add(outbound())
                add(buildJsonObject {
                    put("tag", "direct")
                    put("protocol", "freedom")
                })
            }
        }
        return config.toString()
    }

    private fun outbound(): JsonObject = buildJsonObject {
        put("tag", "proxy")
        when (kind) {
            Kind.VLESS -> {
                put("protocol", "vless")
                putJsonObject("settings") {
                    putJsonArray("vnext") {
                        add(buildJsonObject {
                            put("address", host)
                            put("port", port)
                            putJsonArray("users") {
                                add(buildJsonObject {
                                    put("id", secret)
                                    put("encryption", method.ifEmpty { "none" })
                                    if (flow.isNotEmpty()) put("flow", flow)
                                })
                            }
                        })
                    }
                }
            }
            Kind.VMESS -> {
                put("protocol", "vmess")
                putJsonObject("settings") {
                    putJsonArray("vnext") {
                        add(buildJsonObject {
                            put("address", host)
                            put("port", port)
                            putJsonArray("users") {
                                add(buildJsonObject {
                                    put("id", secret)
                                    put("security", method.ifEmpty { "auto" })
                                })
                            }
                        })
                    }
                }
            }
            Kind.TROJAN -> {
                put("protocol", "trojan")
                putJsonObject("settings") {
                    putJsonArray("servers") {
                        add(buildJsonObject {
                            put("address", host)
                            put("port", port)
                            put("password", secret)
                        })
                    }
                }
            }
            Kind.SHADOWSOCKS -> {
                put("protocol", "shadowsocks")
                putJsonObject("settings") {
                    putJsonArray("servers") {
                        add(buildJsonObject {
                            put("address", host)
                            put("port", port)
                            put("method", method)
                            put("password", secret)
                        })
                    }
                }
            }
        }
        if (kind != Kind.SHADOWSOCKS) put("streamSettings", stream())
    }

    private fun stream(): JsonObject = buildJsonObject {
        put("network", network)
        put("security", security)
        when (security) {
            "reality" -> putJsonObject("realitySettings") {
                put("serverName", sni)
                put("fingerprint", fingerprint.ifEmpty { "chrome" })
                put("publicKey", publicKey)
                if (shortId.isNotEmpty()) put("shortId", shortId)
                if (spiderX.isNotEmpty()) put("spiderX", spiderX)
            }
            "tls" -> putJsonObject("tlsSettings") {
                put("allowInsecure", allowInsecure)
                val serverName = sni.ifEmpty { hostHeader }
                if (serverName.isNotEmpty()) put("serverName", serverName)
                if (fingerprint.isNotEmpty()) put("fingerprint", fingerprint)
                if (alpn.isNotEmpty()) putJsonArray("alpn") { alpn.forEach { add(JsonPrimitive(it)) } }
            }
        }
        when (network) {
            "ws" -> putJsonObject("wsSettings") {
                put("path", path.ifEmpty { "/" })
                if (hostHeader.isNotEmpty()) put("host", hostHeader)
            }
            "grpc" -> putJsonObject("grpcSettings") {
                put("serviceName", serviceName)
                put("multiMode", mode == "multi")
            }
            "xhttp" -> putJsonObject("xhttpSettings") {
                put("path", path.ifEmpty { "/" })
                if (hostHeader.isNotEmpty()) put("host", hostHeader)
                if (mode.isNotEmpty()) put("mode", mode)
            }
            "httpupgrade" -> putJsonObject("httpupgradeSettings") {
                put("path", path.ifEmpty { "/" })
                if (hostHeader.isNotEmpty()) put("host", hostHeader)
            }
            "tcp" -> if (headerType == "http") putJsonObject("tcpSettings") {
                putJsonObject("header") {
                    put("type", "http")
                    putJsonObject("request") {
                        putJsonArray("path") { add(JsonPrimitive(path.ifEmpty { "/" })) }
                        if (hostHeader.isNotEmpty()) putJsonObject("headers") {
                            putJsonArray("Host") { add(JsonPrimitive(hostHeader)) }
                        }
                    }
                }
            }
        }
    }

    companion object {
        /** Порт socks-входа. Слушает только сам телефон. */
        const val SOCKS_PORT = 10808

        private val SCHEMES = listOf("vless://", "vmess://", "trojan://", "ss://")
        private val NETWORKS = setOf("tcp", "ws", "grpc", "xhttp", "httpupgrade", "kcp")

        /** Ссылка из текста: целиком или внутри письма. */
        fun find(input: String): String? {
            val lower = input.lowercase()
            val start = SCHEMES.mapNotNull { scheme -> lower.indexOf(scheme).takeIf { it >= 0 } }
                .minOrNull() ?: return null
            val link = input.substring(start).takeWhile { !it.isWhitespace() && it !in "\"'<>" }
            return link.ifEmpty { null }
        }

        fun looksLikeLink(input: String): Boolean = find(input) != null

        fun parse(input: String): XrayLink {
            val link = find(input) ?: throw ParseException(
                "Это не ключ X-Ray: ожидается ссылка vless://, vmess://, trojan:// или ss://."
            )
            val lower = link.lowercase()
            val result = when {
                lower.startsWith("vmess://") -> parseVmess(link)
                lower.startsWith("ss://") -> parseShadowsocks(link)
                lower.startsWith("vless://") -> parseUserInfo(link, Kind.VLESS)
                else -> parseUserInfo(link, Kind.TROJAN)
            }
            validate(result)
            return result
        }

        private fun parseUserInfo(link: String, kind: Kind): XrayLink {
            val afterScheme = link.substringAfter("://")
            val fragment = afterScheme.substringAfter('#', "")
            val body = afterScheme.substringBefore('#')
            val query = body.substringAfter('?', "")
            val authority = body.substringBefore('?')
            val at = authority.lastIndexOf('@')
            if (at <= 0) throw ParseException("В ключе X-Ray нет идентификатора.")
            val secret = decode(authority.substring(0, at))
            val (host, port) = splitHostPort(authority.substring(at + 1).trim('/'))
                ?: throw ParseException("В ключе X-Ray нет порта.")
            val params = queryItems(query)
            return XrayLink(
                kind = kind,
                host = host,
                port = port,
                secret = secret,
                method = params["encryption"].orEmpty(),
                flow = params["flow"].orEmpty(),
                network = normalizedNetwork(params["type"] ?: "tcp"),
                security = (params["security"] ?: if (kind == Kind.TROJAN) "tls" else "none").lowercase(),
                sni = params["sni"] ?: params["peer"].orEmpty(),
                fingerprint = params["fp"].orEmpty(),
                alpn = params["alpn"].orEmpty().split(',').filter { it.isNotEmpty() },
                publicKey = params["pbk"].orEmpty(),
                shortId = params["sid"].orEmpty(),
                spiderX = params["spx"].orEmpty(),
                path = params["path"].orEmpty(),
                hostHeader = params["host"].orEmpty(),
                serviceName = params["servicename"].orEmpty(),
                mode = params["mode"].orEmpty(),
                headerType = params["headertype"].orEmpty(),
                allowInsecure = params["allowinsecure"]?.lowercase() in setOf("1", "true") ||
                    params["insecure"]?.lowercase() in setOf("1", "true"),
                name = decode(fragment),
            )
        }

        private fun parseVmess(link: String): XrayLink {
            val encoded = link.substring("vmess://".length).substringBefore('#')
            val text = base64(encoded)?.toString(Charsets.UTF_8)
                ?: throw ParseException("Ключ X-Ray с «vmess без JSON внутри» приложение не понимает.")
            val json = runCatching { Json.parseToJsonElement(text).jsonObject }.getOrNull()
                ?: throw ParseException("Ключ X-Ray с «vmess без JSON внутри» приложение не понимает.")
            fun field(key: String): String = runCatching { json[key]?.jsonPrimitive?.content }.getOrNull().orEmpty()
            val port = field("port").toIntOrNull() ?: throw ParseException("В ключе X-Ray нет порта.")
            val network = normalizedNetwork(field("net").ifEmpty { "tcp" })
            return XrayLink(
                kind = Kind.VMESS,
                host = field("add"),
                port = port,
                secret = field("id"),
                method = field("scy").ifEmpty { "auto" },
                network = network,
                security = field("tls").ifEmpty { "none" }.lowercase(),
                sni = field("sni"),
                fingerprint = field("fp"),
                alpn = field("alpn").split(',').filter { it.isNotEmpty() },
                path = field("path"),
                hostHeader = field("host"),
                headerType = field("type"),
                serviceName = if (network == "grpc") field("path") else "",
                name = field("ps"),
            )
        }

        private fun parseShadowsocks(link: String): XrayLink {
            val afterScheme = link.substring("ss://".length)
            val fragment = afterScheme.substringAfter('#', "")
            val main = afterScheme.substringBefore('#').substringBefore('?')
            var userInfo: String
            val hostPort: String
            val at = main.lastIndexOf('@')
            if (at > 0) {
                userInfo = decode(main.substring(0, at))
                hostPort = main.substring(at + 1).trim('/')
                if (!userInfo.contains(':')) {
                    base64(userInfo)?.toString(Charsets.UTF_8)?.let { userInfo = it }
                }
            } else {
                val plain = base64(main)?.toString(Charsets.UTF_8)
                    ?: throw ParseException("В ключе X-Ray нет адреса сервера.")
                val split = plain.lastIndexOf('@')
                if (split <= 0) throw ParseException("В ключе X-Ray нет адреса сервера.")
                userInfo = plain.substring(0, split)
                hostPort = plain.substring(split + 1)
            }
            val colon = userInfo.indexOf(':')
            if (colon <= 0) throw ParseException("В ключе X-Ray нет пароля.")
            val (host, port) = splitHostPort(hostPort) ?: throw ParseException("В ключе X-Ray нет порта.")
            return XrayLink(
                kind = Kind.SHADOWSOCKS,
                host = host,
                port = port,
                secret = userInfo.substring(colon + 1),
                method = userInfo.substring(0, colon),
                name = decode(fragment),
            )
        }

        private fun validate(link: XrayLink) {
            if (link.host.isEmpty()) throw ParseException("В ключе X-Ray нет адреса сервера.")
            if (link.port !in 1..65535) throw ParseException("В ключе X-Ray нет порта.")
            if (link.secret.isEmpty()) throw ParseException("В ключе X-Ray нет идентификатора.")
            if (link.network !in NETWORKS) {
                throw ParseException("Ключ X-Ray с «type=${link.network}» приложение не понимает.")
            }
            if (link.security !in setOf("none", "tls", "reality")) {
                throw ParseException("Ключ X-Ray с «security=${link.security}» приложение не понимает.")
            }
            if (link.security == "reality" && link.publicKey.isEmpty()) {
                throw ParseException("В ключе X-Ray нет ключа Reality (pbk).")
            }
            if (link.kind == Kind.SHADOWSOCKS && link.method.isEmpty()) {
                throw ParseException("В ключе X-Ray нет метода шифрования.")
            }
        }

        private fun normalizedNetwork(value: String): String = when (value.lowercase()) {
            "raw", "" -> "tcp"
            "splithttp" -> "xhttp"
            "websocket" -> "ws"
            "mkcp" -> "kcp"
            else -> value.lowercase()
        }

        internal fun splitHostPort(value: String): Pair<String, Int>? {
            val text = value.substringBefore('/')
            if (text.startsWith("[")) {
                val close = text.indexOf(']')
                if (close < 0) return null
                val port = text.substring(close + 1).removePrefix(":").toIntOrNull() ?: return null
                return text.substring(1, close) to port
            }
            val colon = text.lastIndexOf(':')
            if (colon <= 0) return null
            val port = text.substring(colon + 1).toIntOrNull() ?: return null
            return text.substring(0, colon) to port
        }

        private fun queryItems(query: String): Map<String, String> =
            query.split('&').filter { it.isNotEmpty() }.associate { pair ->
                pair.substringBefore('=').lowercase() to decode(pair.substringAfter('=', ""))
            }

        private fun decode(value: String): String = runCatching {
            URLDecoder.decode(value.replace("+", "%2B"), "UTF-8")
        }.getOrDefault(value).trim()

        internal fun base64(value: String): ByteArray? {
            var text = value.trim().replace('-', '+').replace('_', '/')
            text = runCatching { URLDecoder.decode(text.replace("+", "%2B"), "UTF-8") }.getOrDefault(text)
            while (text.length % 4 != 0) text += "="
            return runCatching { Base64.getDecoder().decode(text) }.getOrNull()
        }
    }
}
