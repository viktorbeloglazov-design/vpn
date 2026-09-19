package kz.qpvpn.model

/**
 * Второй переключатель: рабочие ресурсы.
 *
 * Адреса заложены в приложение. Включён — они идут через VPN, выключен —
 * напрямую, с домашнего адреса. Переключатель работает независимо от главного
 * фильтра и сильнее общих правил: даже когда вся российская зона идёт мимо
 * туннеля, включённый переключатель заворачивает эти адреса в туннель.
 *
 * Маршрутизация в Android идёт по адресам, а не по ссылкам: обе ссылки ведут
 * на один узел, поэтому в маршруты уходит один адрес.
 */
object WorkFilter {

    data class Resource(val title: String, val url: String) {
        /** Узел из ссылки: без схемы, пути и порта. */
        val host: String
            get() = url.substringAfter("://").substringBefore('/').substringBefore(':')
    }

    val resources: List<Resource> = listOf(
        Resource("Ka", "https://135.106.142.73/Ka"),
        Resource("Ka_old", "https://135.106.142.73/Ka_old"),
    )

    /** Узлы без повторов — в таком виде они уходят в маршрутизацию. */
    val hosts: List<String> = resources.map { it.host }.distinct()

    val count: Int get() = resources.size
}
