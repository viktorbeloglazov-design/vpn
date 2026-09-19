package kz.qpvpn.net

import java.net.Inet4Address
import java.net.InetAddress

/** Превращает домены в адреса, которые можно положить в маршруты. */
object DomainResolver {

    fun resolve(host: String): List<Ipv4Net> {
        val addresses = try {
            InetAddress.getAllByName(host)
        } catch (error: Exception) {
            return emptyList()
        }

        return addresses.asSequence()
            .filterIsInstance<Inet4Address>()
            .filter { !it.isLoopbackAddress && !it.isLinkLocalAddress && !it.isAnyLocalAddress }
            .mapNotNull { Cidr.parse(it.hostAddress ?: "") }
            .distinct()
            .toList()
    }

    /** Домен второго уровня обычно стоит брать вместе с www-вариантом. */
    fun resolveWithWww(host: String): List<Ipv4Net> {
        val direct = resolve(host)
        if (host.startsWith("www.") || host.count { it == '.' } != 1) return direct
        return (direct + resolve("www.$host")).distinct()
    }
}
