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

    /**
     * Размер пакета. 0 — подобрать самому.
     *
     * В некоторых сетях пакеты обычного размера не доходят целиком:
     * сообщения отправляются, а видео крутится и не скачивается. Лечится
     * числом поменьше; 1280 проходит почти везде, но и скорость ниже,
     * поэтому подбор идёт сверху вниз.
     */
    val mtu: Int = 0,

    /**
     * Что подобралось в прошлый раз. 0 — ещё не подбирали.
     *
     * Подбор занимает секунды, и повторять его при каждом включении
     * незачем: сеть обычно та же самая.
     */
    val probedMtu: Int = 0,

    /**
     * Вся российская зона идёт мимо туннеля.
     *
     * Работает в режиме «всё через VPN, кроме правил»: из туннеля вычитаются
     * все подсети, выданные России, поэтому российские сайты открываются
     * с домашнего адреса без единого правила.
     */
    val bypassRuZone: Boolean = true,
)

@Serializable
data class AppConfig(
    val version: Int = 1,
    val enabled: Boolean = false,

    /**
     * Весь трафик через VPN.
     *
     * Самый простой режим: туннель забирает всё, включая российские сайты.
     * Перекрывает остальные переключатели.
     */
    val fullTunnel: Boolean = false,

    /**
     * Главный фильтр: через VPN идёт всё, кроме российских адресов.
     *
     * Так заблокированные сервисы работают наверняка: их адреса приложение
     * не угадывает по имени, а просто не оставляет снаружи туннеля. Банки,
     * госуслуги и любые российские сайты при этом идут напрямую — их
     * подсети вычитаются из туннеля целиком.
     *
     * Включён по умолчанию и перекрывает режим маршрутизации — всё остальное
     * настраивается в расширенных настройках.
     */
    val mainFilter: Boolean = true,

    /**
     * Рабочие ресурсы: заложенные в приложение адреса идут через VPN.
     *
     * Выключен — те же адреса идут напрямую.
     */
    val workFilter: Boolean = true,

    // Режим остался в настройках ради старых сохранённых файлов: выбрать
    // его негде, приложение всегда работает как «всё через VPN, кроме правил».
    /**
     * Запасной вход: адрес:порт узла, который пересылает пакеты на сервер.
     *
     * Нужен там, где оператор пропускает не все адреса. Ключ при этом тот
     * же самый — узел ничего не расшифровывает, только перебрасывает, —
     * поэтому меняется ровно одна строка.
     */
    val backupEndpoint: String = "",

    val mode: TunnelMode = TunnelMode.EXCLUDE,
    val rules: List<RoutingRule> = emptyList(),
    val appsMode: AppsMode = AppsMode.OFF,
    val selectedApps: List<String> = emptyList(),
    val options: TunnelOptions = TunnelOptions(),
) {
    val activeRules: List<RoutingRule>
        get() = rules.filter { it.enabled && it.value.isNotBlank() }

    /** Режим, который действительно применяется с учётом переключателей. */
    val effectiveMode: TunnelMode
        get() = when {
            fullTunnel -> TunnelMode.FULL
            mainFilter -> TunnelMode.EXCLUDE
            else -> mode
        }

    /**
     * Настройки, приведённые к зашитому поведению.
     *
     * Маршрутизация не настраивается: заблокированные сервисы всегда идут
     * через VPN, российские адреса — всегда напрямую. Единственное, что
     * человек выбирает сам, — рабочие ресурсы, поэтому [workFilter] здесь
     * не трогается. Остальное приводится к заводскому виду, в том числе
     * настройки, сохранённые прежними версиями программы.
     */
    /**
     * Куда пробовать подключаться, по порядку.
     *
     * Сначала сервер напрямую: так короче путь и выше скорость. Если он
     * не отвечает — через запасной вход.
     */
    fun endpointsToTry(primary: String): List<String> {
        val backup = backupEndpoint.trim()
        return if (backup.isEmpty() || backup == primary) listOf(primary)
        else listOf(primary, backup)
    }

    fun pinned(): AppConfig = copy(
        fullTunnel = false,
        mainFilter = true,
        mode = TunnelMode.EXCLUDE,
        rules = emptyList(),
        appsMode = AppsMode.OFF,
        selectedApps = emptyList(),
        options = options.copy(
            useTunnelDns = true,
            blockIpv6 = true,
            bypassRuZone = true,
        ),
    )
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

    /** Когда сервер отвечал в последний раз, миллисекунды эпохи. 0 — ещё не отвечал. */
    val lastHandshake: Long = 0,
)
