package kz.qpvpn.vpn

import android.content.Context
import android.content.pm.PackageManager
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
import kz.qpvpn.model.AppsMode
import kz.qpvpn.model.ConnectionState
import kz.qpvpn.model.RuleKind
import kz.qpvpn.model.MasterFilter
import kz.qpvpn.model.TunnelMode
import kz.qpvpn.model.TunnelStatus
import kz.qpvpn.model.WorkFilter
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
        // При включённом главном фильтре российская зона вычитается всегда:
        // в этом и состоит его смысл, отдельная галочка тут ни при чём.
        val wantsRuZone = (config.mainFilter || config.options.bypassRuZone) &&
            config.effectiveMode == TunnelMode.EXCLUDE
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
                    state = ConnectionState.CONNECTING,
                    routeCount = routes.size,
                    serverName = profile.endpointHost,
                    message = "Устанавливаю связь с сервером…",
                )

                // Поднятый туннель — ещё не связь. Пока сервер не ответил на
                // рукопожатие, трафик уходит в пустоту, а телефон при этом
                // уже считает, что VPN работает: интернета нет, и непонятно
                // почему. Поэтому дожидаемся ответа и только тогда говорим
                // «подключён».
                if (!awaitHandshake()) {
                    takeDown()
                    fail(
                        "Сервер ${profile.endpointHost} не ответил. Обычно это значит одно из трёх: " +
                            "ключ выдан для другого протокола (нужен AmneziaWG или WireGuard), " +
                            "сервер недоступен, или эта сеть режет VPN — попробуйте мобильный интернет вместо Wi-Fi."
                    )
                    return
                }

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

    /**
     * Ждёт первого рукопожатия с сервером.
     *
     * WireGuard повторяет попытку примерно раз в пять секунд, поэтому
     * двадцати секунд хватает на четыре захода. Молчание дольше — это уже
     * не «медленная сеть», а несовпадение ключа или недоступный сервер.
     */
    private suspend fun awaitHandshake(timeoutMillis: Long = 20_000): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMillis
        while (System.currentTimeMillis() < deadline) {
            delay(1_000)
            if (lastHandshakeMillis() > 0) return true
        }
        return false
    }

    /** Время последнего рукопожатия по данным туннеля, 0 — его ещё не было. */
    private suspend fun lastHandshakeMillis(): Long = try {
        withContext(Dispatchers.IO) {
            val statistics = backend.getStatistics(tunnel)
            statistics.peers().maxOfOrNull { statistics.peer(it)?.latestHandshakeEpochMillis() ?: 0L } ?: 0L
        }
    } catch (error: Exception) {
        0L
    }

    /** Опускает туннель, не трогая показанное состояние. */
    private suspend fun takeDown() {
        try {
            withContext(Dispatchers.IO) {
                backend.setState(tunnel, Tunnel.State.DOWN, null)
            }
        } catch (error: Exception) {
            // Туннель мог не подняться вовсе — тогда и опускать нечего.
        }
        appliedRoutes = emptyList()
    }

    /**
     * Сверяет показанное состояние с настоящим.
     *
     * Приложение могли закрыть или выгрузить из памяти, а туннель при этом
     * остаётся поднятым системой. Без сверки экран показывает «Выключен»,
     * пока телефон сидит в туннеле — и человек не понимает, почему нет сети.
     */
    suspend fun syncState() {
        val up = try {
            withContext(Dispatchers.IO) { backend.getState(tunnel) } == Tunnel.State.UP
        } catch (error: Exception) {
            false
        }

        if (up && _status.value.state != ConnectionState.CONNECTED) {
            val profile = store.profileText()?.let { text ->
                runCatching { WgProfile.parse(text) }.getOrNull()
            }
            _status.value = TunnelStatus(
                state = ConnectionState.CONNECTED,
                connectedSince = System.currentTimeMillis(),
                routeCount = appliedRoutes.size,
                serverName = profile?.endpointHost.orEmpty(),
            )
            startWatching()
        } else if (!up && _status.value.state == ConnectionState.CONNECTED) {
            watchJob?.cancel()
            watchJob = null
            _status.value = TunnelStatus()
        }
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
        val useRuZone = (config.mainFilter || config.options.bypassRuZone) &&
            config.effectiveMode == TunnelMode.EXCLUDE
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
        if (withIpv6) {
            // IPv6 заворачиваем в туннель всегда: иначе телефон в мобильной
            // сети откроет заблокированный сайт по IPv6 мимо VPN — и фильтр
            // будет выглядеть неработающим.
            allowed += "::/0"
        }

        val apps = appsFor(config)

        val text = profile.toConfigText(
            allowedIps = allowed,
            includeDns = config.options.useTunnelDns && config.effectiveMode != TunnelMode.INCLUDE,
            appsMode = if (apps.isEmpty()) AppsMode.OFF else config.appsMode,
            apps = apps,
        )

        val parsed = Config.parse(BufferedReader(StringReader(text)))
        withContext(Dispatchers.IO) {
            backend.setState(tunnel, Tunnel.State.UP, parsed)
        }
    }

    /** Считает список подсетей, которые должны уходить в туннель. */
    private suspend fun routesFor(config: AppConfig, profile: WgProfile, useRuZone: Boolean): List<String> {
        val nets = resolveRules(config)
        val work = workNets()

        return when (config.effectiveMode) {
            TunnelMode.FULL -> if (config.workFilter || work.isEmpty()) {
                listOf("0.0.0.0/0")
            } else {
                // Рабочие ресурсы выключены — вычитаем их из полного туннеля.
                Cidr.complement(work).map { it.toString() }
            }

            TunnelMode.INCLUDE -> {
                val included = if (config.workFilter) nets + work else nets
                if (included.isEmpty()) {
                    // Пустой список туннель не примет: оставляем адрес самого клиента,
                    // фактически в туннель не уходит ничего.
                    listOf(profile.addresses.firstOrNull()?.substringBefore('/')?.plus("/32") ?: "0.0.0.0/32")
                } else {
                    Cidr.merge(included).map { it.toString() }
                }
            }

            TunnelMode.EXCLUDE -> {
                // Кроме правил пользователя из туннеля вычитается вся
                // российская зона, если это включено в настройках.
                val excluded = if (useRuZone) {
                    nets + RuZone.networks(context)
                } else {
                    nets
                }
                if (config.workFilter) {
                    // Рабочие ресурсы сильнее исключений: возвращаем их в туннель,
                    // даже если они попали в российскую зону.
                    val base = if (excluded.isEmpty()) listOf(Ipv4Net(0, 0)) else Cidr.complement(excluded)
                    Cidr.merge(base + work).map { it.toString() }
                } else {
                    val all = excluded + work
                    if (all.isEmpty()) listOf("0.0.0.0/0")
                    else Cidr.complement(all).map { it.toString() }
                }
            }
        }
    }

    /** Адреса рабочих ресурсов: заложенные в приложение узлы. */
    private suspend fun workNets(): List<Ipv4Net> {
        val result = mutableListOf<Ipv4Net>()
        val domains = mutableListOf<String>()
        for (host in WorkFilter.hosts) {
            val net = Cidr.parse(host)
            if (net != null) result += net else domains += host.lowercase()
        }
        if (domains.isNotEmpty()) {
            result += DomainResolver.resolveAll(domains)
        }
        return result.distinct()
    }

    /**
     * Какие программы перечислять туннелю.
     *
     * Когда включён главный фильтр, к выбранным вручную добавляется встроенный
     * список программ, которым нужен зарубежный адрес: иначе в режиме «только
     * выбранные» человеку пришлось бы отмечать их по одной. Имена, которых на
     * телефоне нет, отсеиваются — система откажется поднимать туннель с чужим
     * пакетом в списке.
     */
    private fun appsFor(config: AppConfig): List<String> {
        if (config.appsMode == AppsMode.OFF) return emptyList()

        val wanted = if (config.appsMode == AppsMode.ONLY_SELECTED && config.mainFilter) {
            config.selectedApps + MasterFilter.packages
        } else {
            config.selectedApps
        }

        val manager = context.packageManager
        return wanted.distinct().filter { name ->
            name != context.packageName && isInstalled(manager, name)
        }
    }

    private fun isInstalled(manager: PackageManager, name: String): Boolean = try {
        manager.getPackageInfo(name, 0)
        true
    } catch (error: PackageManager.NameNotFoundException) {
        false
    }

    /**
     * Разворачивает правила пользователя в адреса.
     *
     * Встроенный список сервисов здесь не участвует. В режиме «всё через VPN,
     * кроме российской зоны» правила означают обратное — что идёт мимо
     * туннеля, — а заблокированные сервисы и так внутри: снаружи остаётся
     * только российское адресное пространство.
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

                // Связь могла пропасть: сервер перестал отвечать, а туннель
                // при этом поднят — трафик уходит в никуда.
                val handshake = lastHandshakeMillis()
                if (handshake > 0) {
                    val silence = System.currentTimeMillis() - handshake
                    _status.value = _status.value.copy(
                        message = if (silence > 180_000)
                            "Сервер молчит больше трёх минут — связь потеряна."
                        else _status.value.message.takeIf { !it.startsWith("Сервер молчит") }.orEmpty(),
                    )
                }

                sinceResolve += 2_000
                val interval = store.config.value.options.reresolveMinutes.coerceIn(1, 60) * 60_000L
                val current = store.config.value
                val hasDomains = current.activeRules.any { it.kind == RuleKind.DOMAIN }
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
