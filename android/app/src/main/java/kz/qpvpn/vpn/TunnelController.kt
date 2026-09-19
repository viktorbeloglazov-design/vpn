package kz.qpvpn.vpn

import android.content.Context
import org.amnezia.awg.backend.Backend
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.Tunnel
import org.amnezia.awg.config.Config
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kz.qpvpn.data.Store
import kz.qpvpn.model.AppConfig
import kz.qpvpn.model.ConnectionState
import kz.qpvpn.model.RuleKind
import kz.qpvpn.model.MasterFilter
import kz.qpvpn.model.TunnelMode
import kz.qpvpn.model.TunnelStatus
import kz.qpvpn.net.Cidr
import kz.qpvpn.net.DomainResolver
import kz.qpvpn.net.Ipv4Net
import kz.qpvpn.net.RuZone
import java.io.BufferedReader
import java.io.StringReader

/**
 * Поднимает и перестраивает туннель.
 *
 * Работает через библиотеку AmneziaWG: она понимает и обычный WireGuard,
 * и его версию с маскировкой, поэтому оба вида профилей поднимаются одинаково.
 *
 * Вся маршрутизация на Android задаётся одним списком AllowedIPs: туда попадает
 * то, что должно идти через VPN. Для режима «всё кроме правил» список считается
 * как дополнение — поэтому исключения работают без отдельных системных маршрутов.
 */
class TunnelController(
    private val context: Context,
    private val store: Store,
) {

    private val backend: Backend by lazy { GoBackend(context) }

    private val tunnel = object : Tunnel {
        override fun getName(): String = "qpvpn"
        override fun onStateChange(newState: Tunnel.State) {
            if (newState == Tunnel.State.DOWN && _status.value.state == ConnectionState.CONNECTED) {
                _status.value = _status.value.copy(state = ConnectionState.DISCONNECTED)
            }
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var watchJob: Job? = null
    private var appliedRoutes: List<String> = emptyList()

    private val _status = MutableStateFlow(TunnelStatus())
    val status: StateFlow<TunnelStatus> = _status.asStateFlow()

    // MARK: - Управление

    suspend fun connect() {
        val profileText = store.profileText()
        if (profileText.isNullOrBlank()) {
            fail("Профиль не загружен. Откройте вкладку «Профиль» и выберите файл .conf.")
            return
        }

        _status.value = _status.value.copy(state = ConnectionState.CONNECTING, message = "")

        val profile = try {
            WgProfile.parse(profileText)
        } catch (error: Exception) {
            fail(error.message ?: "Профиль не удалось прочитать.")
            return
        }

        val config = store.config.value
        val wantsRuZone = config.options.bypassRuZone && config.effectiveMode == TunnelMode.EXCLUDE
        val wantsIpv6 = config.options.blockIpv6 || profile.hasIpv6Address

        // Попытки от полной к упрощённой. Российский список — это тысячи
        // маршрутов, и если система откажется их принять, лучше подключиться
        // без него и честно об этом сказать, чем оставить человека без связи.
        val attempts = buildList {
            add(Triple(wantsRuZone, wantsIpv6, ""))
            if (wantsIpv6) add(Triple(wantsRuZone, false, ""))
            if (wantsRuZone) {
                add(Triple(false, wantsIpv6, "Список адресов России телефон не принял — подключение без него."))
                add(Triple(false, false, "Список адресов России телефон не принял — подключение без него."))
            }
        }

        var lastError: Exception? = null
        for ((useRuZone, withIpv6, note) in attempts) {
            val routes = routesFor(config, profile, useRuZone)
            try {
                applyConfig(profile, config, routes, withIpv6 = withIpv6)
                appliedRoutes = routes
                _status.value = TunnelStatus(
                    state = ConnectionState.CONNECTED,
                    connectedSince = System.currentTimeMillis(),
                    routeCount = routes.size,
                    serverName = profile.endpointHost,
                    message = note,
                )
                startWatching()
                return
            } catch (error: Exception) {
                lastError = error
            }
        }

        fail(lastError?.message ?: "Не удалось поднять туннель.")
    }

    suspend fun disconnect() {
        watchJob?.cancel()
        watchJob = null
        try {
            withContext(Dispatchers.IO) {
                backend.setState(tunnel, Tunnel.State.DOWN, null)
            }
        } catch (error: Exception) {
            // Туннель мог уже упасть сам — состояние всё равно сбрасываем.
        }
        appliedRoutes = emptyList()
        _status.value = TunnelStatus(state = ConnectionState.DISCONNECTED)
    }

    /** Перестраивает маршруты после правки правил, не разрывая соединение без нужды. */
    suspend fun refreshRoutes() {
        if (_status.value.state != ConnectionState.CONNECTED) return
        val profileText = store.profileText() ?: return
        val profile = try {
            WgProfile.parse(profileText)
        } catch (error: Exception) {
            return
        }

        val config = store.config.value
        val useRuZone = config.options.bypassRuZone && config.effectiveMode == TunnelMode.EXCLUDE
        val routes = routesFor(config, profile, useRuZone)
        if (routes == appliedRoutes) return

        try {
            applyConfig(profile, config, routes, withIpv6 = config.options.blockIpv6 || profile.hasIpv6Address)
            appliedRoutes = routes
            _status.value = _status.value.copy(routeCount = routes.size)
        } catch (error: Exception) {
            _status.value = _status.value.copy(message = "Маршруты не обновились: ${error.message}")
        }
    }

    // MARK: - Внутреннее

    private suspend fun applyConfig(
        profile: WgProfile,
        config: AppConfig,
        routes: List<String>,
        withIpv6: Boolean,
    ) {
        val allowed = routes.toMutableList()
        if (withIpv6 && config.effectiveMode != TunnelMode.INCLUDE) {
            allowed += "::/0"
        }

        val text = profile.toConfigText(
            allowedIps = allowed,
            includeDns = config.options.useTunnelDns && config.effectiveMode != TunnelMode.INCLUDE,
            appsMode = config.appsMode,
            apps = config.selectedApps,
        )

        val parsed = Config.parse(BufferedReader(StringReader(text)))
        withContext(Dispatchers.IO) {
            backend.setState(tunnel, Tunnel.State.UP, parsed)
        }
    }

    /** Считает список подсетей, которые должны уходить в туннель. */
    private suspend fun routesFor(config: AppConfig, profile: WgProfile, useRuZone: Boolean): List<String> {
        val nets = resolveRules(config)

        return when (config.effectiveMode) {
            TunnelMode.FULL -> listOf("0.0.0.0/0")

            TunnelMode.INCLUDE -> if (nets.isEmpty()) {
                // Пустой список туннель не примет: оставляем адрес самого клиента,
                // фактически в туннель не уходит ничего.
                listOf(profile.addresses.firstOrNull()?.substringBefore('/')?.plus("/32") ?: "0.0.0.0/32")
            } else {
                Cidr.merge(nets).map { it.toString() }
            }

            TunnelMode.EXCLUDE -> {
                // Кроме правил пользователя из туннеля вычитается вся
                // российская зона, если это включено в настройках.
                val excluded = if (useRuZone) {
                    nets + RuZone.networks(context)
                } else {
                    nets
                }
                if (excluded.isEmpty()) {
                    listOf("0.0.0.0/0")
                } else {
                    Cidr.complement(excluded).map { it.toString() }
                }
            }
        }
    }

    /**
     * Разворачивает правила в адреса.
     *
     * Когда включён главный фильтр, к правилам пользователя добавляется
     * встроенный список сервисов, которые не работают с российского адреса.
     */
    private suspend fun resolveRules(config: AppConfig): List<Ipv4Net> {
        val result = mutableListOf<Ipv4Net>()
        val domains = mutableListOf<String>()

        for (rule in config.activeRules) {
            when (rule.kind) {
                RuleKind.CIDR -> Cidr.parse(rule.value)?.let { result += it }
                RuleKind.DOMAIN -> domains += rule.value.trim().lowercase()
            }
        }

        if (config.mainFilter) {
            domains += MasterFilter.domains
        }

        if (domains.isNotEmpty()) {
            result += DomainResolver.resolveAll(domains)
        }
        return result.distinct()
    }

    /** Фоновая работа, пока туннель поднят: счётчики и пересчёт доменов. */
    private fun startWatching() {
        watchJob?.cancel()
        watchJob = scope.launch {
            var sinceResolve = 0L
            while (isActive) {
                delay(2_000)

                val statistics = try {
                    backend.getStatistics(tunnel)
                } catch (error: Exception) {
                    null
                }
                if (statistics != null) {
                    _status.value = _status.value.copy(
                        rxBytes = statistics.totalRx(),
                        txBytes = statistics.totalTx(),
                    )
                }

                sinceResolve += 2_000
                val interval = store.config.value.options.reresolveMinutes.coerceIn(1, 60) * 60_000L
                val hasDomains = store.config.value.activeRules.any { it.kind == RuleKind.DOMAIN }
                if (hasDomains && sinceResolve >= interval) {
                    sinceResolve = 0
                    refreshRoutes()
                }
            }
        }
    }

    private fun fail(message: String) {
        _status.value = TunnelStatus(state = ConnectionState.ERROR, message = message)
    }
}
