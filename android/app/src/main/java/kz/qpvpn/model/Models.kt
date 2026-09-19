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
