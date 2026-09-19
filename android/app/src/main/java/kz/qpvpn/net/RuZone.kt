package kz.qpvpn.net

import android.content.Context
import kz.qpvpn.R

/**
 * Российское адресное пространство.
 *
 * Правило «вся зона .ru мимо VPN» нельзя выразить доменами: домен живёт на
 * адресе, а решение о маршруте принимается именно по адресу. Поэтому в
 * программу вшит список подсетей, выданных России, — по сводкам распределения
 * адресов RIPE. Все они вычитаются из туннеля, и российские сайты, банки и
 * госуслуги идут напрямую, что бы ни было написано в их домене.
 */
object RuZone {

    @Volatile
    private var cached: List<Ipv4Net>? = null

    /** Подсети России. Файл читается один раз за запуск. */
    fun networks(context: Context): List<Ipv4Net> {
        cached?.let { return it }

        val parsed = synchronized(this) {
            cached ?: loadFromResources(context).also { cached = it }
        }
        return parsed
    }

    val isLoaded: Boolean get() = cached != null

    fun count(context: Context): Int = networks(context).size

    private fun loadFromResources(context: Context): List<Ipv4Net> {
        val result = ArrayList<Ipv4Net>(9000)
        try {
            context.resources.openRawResource(R.raw.ru_ipv4).bufferedReader().useLines { lines ->
                for (line in lines) {
                    val text = line.trim()
                    if (text.isEmpty() || text.startsWith("#")) continue
                    Cidr.parse(text)?.let { result += it }
                }
            }
        } catch (error: Exception) {
            return emptyList()
        }
        return result
    }
}
