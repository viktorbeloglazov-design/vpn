package kz.qpvpn.model

import kz.qpvpn.net.Cidr

/**
 * Свои сайты и адреса, которые человек добавляет через VPN сам.
 *
 * Зашитый список закрывает обычные нужды, но не все: кому-то нужен свой
 * сайт, редкий сервис, рабочий адрес за границей. Поле для этого — одно,
 * и правила в нём пишутся как на бумаге: по одному в строке.
 *
 * Разбор нарочно терпимый. Человек впишет и `example.com`, и
 * `https://example.com/page`, и имя с портом, и адрес сети — всё это
 * должно сработать, а не вызвать ругань про формат.
 *
 * Логика обязана совпадать с версией для Mac: одно и то же поле на двух
 * устройствах должно понимать одно и то же.
 */
object OwnRules {

    /** Разбирает то, что человек вписал в поле. */
    fun parse(text: String): List<RoutingRule> {
        val result = mutableListOf<RoutingRule>()
        val seen = mutableSetOf<String>()

        for (line in text.split('\n', ',')) {
            val rule = rule(line) ?: continue
            if (!seen.add("${rule.kind}:${rule.value}")) continue
            result += rule
        }
        return result
    }

    /**
     * Строки, которые человек вписал, но понять их не вышло.
     *
     * Нужны, чтобы сказать об этом на экране: молча проглотить опечатку
     * хуже, чем сказать «эту строку не понял».
     */
    fun unreadable(text: String): List<String> =
        text.split('\n', ',')
            .map { it.trim() }
            .filter { it.isNotEmpty() && rule(it) == null }

    /** Обратно в текст для поля — чтобы человек видел то, что сохранилось. */
    fun text(rules: List<RoutingRule>): String =
        rules.joinToString("\n") { it.value }

    private fun rule(line: String): RoutingRule? {
        var value = line.trim().lowercase()
        if (value.isEmpty() || value.startsWith("#")) return null

        // Человек нередко вставляет ссылку целиком — берём из неё имя.
        for (prefix in listOf("https://", "http://")) {
            if (value.startsWith(prefix)) value = value.removePrefix(prefix)
        }
        val slash = value.indexOf('/')
        if (slash >= 0) {
            // Путь после имени нам не нужен, а «/24» в адресе сети — нужен.
            val tail = value.substring(slash + 1)
            if (tail.isEmpty() || !tail.all { it.isDigit() }) {
                value = value.substring(0, slash)
            }
        }
        // Порт и пользователя тоже отбрасываем: маршрут прокладывается
        // до узла, а не до порта.
        val at = value.lastIndexOf('@')
        if (at >= 0) value = value.substring(at + 1)
        val colon = value.indexOf(':')
        if (colon >= 0 && !value.contains("::")) value = value.substring(0, colon)
        value = value.trim('.', ' ')
        if (value.isEmpty()) return null

        Cidr.normalizeCidr(value)?.let {
            return RoutingRule(kind = RuleKind.CIDR, value = it, note = "своё")
        }
        if (Cidr.isDomain(value)) {
            return RoutingRule(kind = RuleKind.DOMAIN, value = value, note = "своё")
        }
        return null
    }
}
