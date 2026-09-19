package kz.qpvpn.vpn

import kz.qpvpn.model.AppsMode

/** Разобранный профиль WireGuard. */
data class WgProfile(
    val privateKey: String,
    val addresses: List<String>,
    val dns: List<String>,
    val mtu: Int,
    val publicKey: String,
    val presharedKey: String,
    val endpoint: String,
    val keepalive: Int,
    /** Параметры маскировки AmneziaWG, если они были в файле. */
    val amneziaParams: Map<String, String> = emptyMap(),
) {
    /** Профиль сделан под AmneziaWG — обычный WireGuard такой сервер не примет. */
    val isAmnezia: Boolean get() = amneziaParams.isNotEmpty()

    val protocolName: String get() = if (isAmnezia) "AmneziaWG" else "WireGuard"

    val hasIpv6Address: Boolean get() = addresses.any { it.contains(":") }

    val endpointHost: String
        get() = endpoint.substringBeforeLast(':', "")

    /**
     * Собирает текст конфигурации для библиотеки WireGuard.
     *
     * AllowedIPs здесь — главное: именно этот список решает, что пойдёт
     * в туннель. Списки программ передаются теми же полями, что понимает
     * официальное приложение WireGuard.
     */
    fun toConfigText(
        allowedIps: List<String>,
        includeDns: Boolean,
        appsMode: AppsMode,
        apps: List<String>,
    ): String = buildString {
        appendLine("[Interface]")
        appendLine("PrivateKey = $privateKey")
        appendLine("Address = ${addresses.joinToString(", ")}")
        appendLine("MTU = $mtu")
        if (includeDns && dns.isNotEmpty()) {
            appendLine("DNS = ${dns.joinToString(", ")}")
        }
        if (apps.isNotEmpty()) {
            when (appsMode) {
                AppsMode.ONLY_SELECTED -> appendLine("IncludedApplications = ${apps.joinToString(", ")}")
                AppsMode.EXCEPT_SELECTED -> appendLine("ExcludedApplications = ${apps.joinToString(", ")}")
                AppsMode.OFF -> Unit
            }
        }
        appendLine()
        appendLine("[Peer]")
        appendLine("PublicKey = $publicKey")
        if (presharedKey.isNotEmpty()) {
            appendLine("PresharedKey = $presharedKey")
        }
        appendLine("Endpoint = $endpoint")
        appendLine("AllowedIPs = ${allowedIps.joinToString(", ")}")
        if (keepalive > 0) {
            appendLine("PersistentKeepalive = $keepalive")
        }
    }

    companion object {

        class ParseError(message: String) : Exception(message)

        private fun isKey(value: String): Boolean =
            value.length == 44 && value.endsWith("=")

        /** Разбирает обычный файл .conf, который выдаёт сервер. */
        fun parse(text: String): WgProfile {
            var section = ""
            val iface = mutableMapOf<String, String>()
            val peer = mutableMapOf<String, String>()

            for (rawLine in text.lines()) {
                val line = rawLine.substringBefore('#').trim()
                if (line.isEmpty()) continue
                if (line.startsWith("[") && line.endsWith("]")) {
                    section = line.drop(1).dropLast(1).lowercase()
                    continue
                }
                val separator = line.indexOf('=')
                if (separator < 0) continue
                val key = line.substring(0, separator).trim().lowercase()
                val value = line.substring(separator + 1).trim()
                when (section) {
                    "interface" -> iface[key] = value
                    "peer" -> if (!peer.containsKey(key)) peer[key] = value
                }
            }

            if (iface.isEmpty()) throw ParseError("В конфиге нет секции [Interface].")
            if (peer.isEmpty()) throw ParseError("В конфиге нет секции [Peer].")

            val privateKey = iface["privatekey"].orEmpty()
            if (privateKey.isEmpty()) throw ParseError("В конфиге не хватает поля PrivateKey.")
            if (!isKey(privateKey)) throw ParseError("Приватный ключ имеет неверный формат.")

            val publicKey = peer["publickey"].orEmpty()
            if (publicKey.isEmpty()) throw ParseError("В конфиге не хватает поля PublicKey.")
            if (!isKey(publicKey)) throw ParseError("Публичный ключ сервера имеет неверный формат.")

            val endpoint = peer["endpoint"].orEmpty()
            if (endpoint.isEmpty()) throw ParseError("В конфиге не хватает поля Endpoint.")
            if (!endpoint.contains(':')) throw ParseError("Endpoint должен быть в виде адрес:порт.")

            val addresses = splitList(iface["address"].orEmpty())
            if (addresses.isEmpty()) throw ParseError("В конфиге не хватает поля Address.")

            val presharedKey = peer["presharedkey"].orEmpty()
            if (presharedKey.isNotEmpty() && !isKey(presharedKey)) {
                throw ParseError("Preshared-ключ имеет неверный формат.")
            }

            // Amnezia добавляет в [Interface] параметры маскировки: размеры
            // мусорных пакетов и подменённые заголовки. Обычный WireGuard их
            // не понимает, поэтому запоминаем отдельно.
            val amneziaKeys = listOf("jc", "jmin", "jmax", "s1", "s2", "h1", "h2", "h3", "h4")
            val amnezia = amneziaKeys.mapNotNull { key ->
                iface[key]?.let { key to it }
            }.toMap()

            return WgProfile(
                privateKey = privateKey,
                addresses = addresses,
                dns = splitList(iface["dns"].orEmpty()),
                mtu = iface["mtu"]?.toIntOrNull()?.coerceIn(1200, 1500) ?: 1420,
                publicKey = publicKey,
                presharedKey = presharedKey,
                endpoint = endpoint,
                keepalive = peer["persistentkeepalive"]?.toIntOrNull() ?: 25,
                amneziaParams = amnezia,
            )
        }

        fun splitList(value: String): List<String> =
            value.split(',', ' ').map { it.trim() }.filter { it.isNotEmpty() }
    }
}
