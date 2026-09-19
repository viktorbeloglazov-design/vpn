package kz.qpvpn.model

import kotlinx.serialization.Serializable
import java.util.UUID

/** Что уходит в туннель. */
@Serializable
enum class TunnelMode {
    /** Весь трафик через VPN. */
    FULL,

    /** Через VPN идут только адреса из правил. */
    INCLUDE,

    /** Через VPN идёт всё, кроме адресов из правил. */
    EXCLUDE;

    val title: String
        get() = when (this) {
            FULL -> "Весь трафик через VPN"
            INCLUDE -> "Только правила через VPN"
            EXCLUDE -> "Всё через VPN, кроме правил"
        }

    val subtitle: String
        get() = when (this) {
            FULL -> "Казахстанский адрес для всех соединений."
            INCLUDE -> "Обычный интернет остаётся прямым, в туннель уходят только выбранные сайты."
            EXCLUDE -> "Казахстанский адрес по умолчанию, перечисленные сайты идут напрямую."
        }
}

@Serializable
enum class RuleKind {
    DOMAIN,
    CIDR;

    val title: String
        get() = if (this == DOMAIN) "Домен" else "IP / подсеть"
}

@Serializable
data class RoutingRule(
    val id: String = UUID.randomUUID().toString(),
    val kind: RuleKind,
    val value: String,
    val enabled: Boolean = true,
    val note: String = "",
)

/** Как обходиться со списком выбранных программ. */
@Serializable
enum class AppsMode {
    /** Правила по приложениям выключены. */
    OFF,

    /** В туннель попадают только выбранные программы. */
    ONLY_SELECTED,

    /** Выбранные программы идут мимо туннеля. */
    EXCEPT_SELECTED;

    val title: String
        get() = when (this) {
            OFF -> "Все программы одинаково"
            ONLY_SELECTED -> "Только выбранные — через VPN"
            EXCEPT_SELECTED -> "Выбранные — мимо VPN"
        }
}

@Serializable
data class TunnelOptions(
    /** Использовать DNS-серверы из профиля. */
    val useTunnelDns: Boolean = true,

    /** Заворачивать IPv6 в туннель, чтобы настоящий адрес не утёк. */
    val blockIpv6: Boolean = true,

    /** Как часто пересчитывать адреса доменов, минут. */
    val reresolveMinutes: Int = 5,
)

@Serializable
data class AppConfig(
    val version: Int = 1,
    val enabled: Boolean = false,
    val mode: TunnelMode = TunnelMode.FULL,
    val rules: List<RoutingRule> = emptyList(),
    val appsMode: AppsMode = AppsMode.OFF,
    val selectedApps: List<String> = emptyList(),
    val options: TunnelOptions = TunnelOptions(),
) {
    val activeRules: List<RoutingRule>
        get() = rules.filter { it.enabled && it.value.isNotBlank() }
}

enum class ConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    ERROR;

    val title: String
        get() = when (this) {
            DISCONNECTED -> "Выключен"
            CONNECTING -> "Подключение…"
            CONNECTED -> "Подключён"
            ERROR -> "Ошибка"
        }
}

data class TunnelStatus(
    val state: ConnectionState = ConnectionState.DISCONNECTED,
    val message: String = "",
    val connectedSince: Long = 0,
    val rxBytes: Long = 0,
    val txBytes: Long = 0,
    val routeCount: Int = 0,
    val serverName: String = "",
)

/** Готовые наборы правил — те же, что в версии для Mac. */
data class RulePreset(
    val id: String,
    val title: String,
    val mode: TunnelMode,
    val values: List<Pair<RuleKind, String>>,
) {
    fun rules(): List<RoutingRule> = values.map { (kind, value) ->
        RoutingRule(kind = kind, value = value, note = title)
    }
}

object Presets {
    private fun domains(vararg hosts: String) = hosts.map { RuleKind.DOMAIN to it }

    val all: List<RulePreset> = listOf(
        RulePreset(
            "kz-services", "Сервисы Казахстана", TunnelMode.INCLUDE,
            domains(
                "kaspi.kz", "halykbank.kz", "homebank.kz", "egov.kz", "gov.kz",
                "salyk.kz", "olx.kz", "kolesa.kz", "krisha.kz", "market.kz",
                "wildberries.kz", "beeline.kz", "kcell.kz", "tele2.kz", "2gis.kz",
            ),
        ),
        RulePreset(
            "ru-banking", "Банки и госуслуги РФ", TunnelMode.EXCLUDE,
            domains(
                "sberbank.ru", "online.sberbank.ru", "alfabank.ru", "tbank.ru",
                "tinkoff.ru", "vtb.ru", "gosuslugi.ru", "nalog.gov.ru", "cbr.ru",
            ),
        ),
        RulePreset(
            "ru-marketplaces", "Маркетплейсы РФ", TunnelMode.EXCLUDE,
            domains(
                "wildberries.ru", "seller.wildberries.ru", "ozon.ru", "seller.ozon.ru",
                "market.yandex.ru", "partner.market.yandex.ru", "megamarket.ru",
            ),
        ),
        RulePreset(
            "cn-suppliers", "Китайские поставщики", TunnelMode.EXCLUDE,
            domains("1688.com", "alibaba.com", "taobao.com", "tmall.com", "aliexpress.com", "wechat.com"),
        ),
        RulePreset(
            "local-net", "Локальная сеть", TunnelMode.EXCLUDE,
            listOf(
                RuleKind.CIDR to "10.0.0.0/8",
                RuleKind.CIDR to "172.16.0.0/12",
                RuleKind.CIDR to "192.168.0.0/16",
            ),
        ),
        RulePreset(
            "video-calls", "Видеозвонки", TunnelMode.EXCLUDE,
            domains("zoom.us", "teams.microsoft.com", "meet.google.com", "telegram.org"),
        ),
    )
}
