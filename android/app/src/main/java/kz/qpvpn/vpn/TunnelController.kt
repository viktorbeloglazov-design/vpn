package kz.qpvpn.vpn

import android.content.Context
import android.content.Intent
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
import kz.qpvpn.model.KeepInTunnel
import kz.qpvpn.model.DirectApps
import kz.qpvpn.model.TunnelMode
import kz.qpvpn.model.TunnelStatus
import kz.qpvpn.model.WorkFilter
import kz.qpvpn.net.BulkCheck
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

    private companion object {
        /**
         * Столько маршрутов Android принимает спокойно. Дальше посылка
         * системе разрастается до предела межпроцессного сообщения, и
         * туннель не поднимается.
         */
        const val MAX_ROUTES = 4_000

        /** Шаги укрупнения: насколько большой промежуток между подсетями прощаем. */
        val GAPS = listOf(4_096L, 16_384L, 65_536L, 262_144L, 1_048_576L)

        /** Столько ждём ответа, пока шлём, прежде чем поднимать туннель заново. */
        const val SILENCE_MILLIS = 45_000L

        /**
         * Размеры пакета сверху вниз: чем больше, тем быстрее.
         *
         * 1280 — нижняя ступень: столько обязана пропускать любая сеть,
         * это минимум, заданный самим протоколом IPv6.
         */
        val MTU_LADDER = listOf(1420, 1380, 1320, 1280)
    }

    private val backend: Backend by lazy { GoBackend(context) }

    private val tunnel = object : Tunnel {
        override fun getName(): String = "qpvpn"
        override fun onStateChange(newState: Tunnel.State) {
            if (newState == Tunnel.State.DOWN && _status.value.state == ConnectionState.CONNECTED) {
                publish(_status.value.copy(state = ConnectionState.DISCONNECTED))
            }
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var watchJob: Job? = null
    private var appliedRoutes: List<String> = emptyList()
    private var lastZoneRoutes = 0

    /**
     * Готовая российская зона: считается один раз за запуск.
     *
     * Расчёт перебирает девять тысяч подсетей по нескольку раз. Файл при
     * этом не меняется, так что второй раз считать нечего — а подключение
     * от этого происходит заметно быстрее.
     */
    @Volatile
    private var cachedZone: List<Ipv4Net>? = null

    /** Найденные на телефоне программы, которым туннель показывать нельзя. */
    @Volatile
    private var cachedDirectApps: List<String>? = null

    private val link = LinkWatch(silenceMillis = SILENCE_MILLIS)

    private val _status = MutableStateFlow(TunnelStatus())
    val status: StateFlow<TunnelStatus> = _status.asStateFlow()

    /**
     * Показывает состояние на экране и в строке состояния телефона.
     *
     * Значок наверху обязан появляться ровно тогда, когда туннель поднят,
     * поэтому состояние меняется только здесь — иначе где-нибудь забудется.
     */
    private fun publish(status: TunnelStatus) {
        _status.value = status
        when (status.state) {
            ConnectionState.CONNECTED -> VpnNotification.show(
                context,
                connected = true,
                server = status.serverName,
                rxBytes = status.rxBytes,
                txBytes = status.txBytes,
            )

            ConnectionState.CONNECTING -> VpnNotification.show(
                context,
                connected = false,
                server = status.serverName,
                rxBytes = 0,
                txBytes = 0,
            )

            else -> VpnNotification.hide(context)
        }
    }

    /** Кнопка «Отключить» из уведомления: работает и когда экран закрыт. */
    fun requestDisconnect() {
        scope.launch { disconnect() }
    }

    // MARK: - Управление

    suspend fun connect() {
        val profileText = store.profileText()
        if (profileText.isNullOrBlank()) {
            fail("Профиль не загружен. Откройте вкладку «Профиль» и выберите файл .conf.")
            return
        }

        publish(_status.value.copy(state = ConnectionState.CONNECTING, message = ""))

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

        // Входов может быть два: сам сервер и узел-пересыльщик. Там, где
        // оператор пропускает не все адреса, до сервера напрямую не достучаться,
        // а до узла — да; ключ при этом один и тот же.
        val endpoints = config.endpointsToTry(profile.endpoint)

        var lastError: Exception? = null
        for ((useRuZone, withIpv6, note) in attempts) {
            val routes = routesFor(config, profile, useRuZone)

            for ((index, endpoint) in endpoints.withIndex()) {
                val viaBackup = index > 0
                val last = index == endpoints.lastIndex
                val attempt = if (viaBackup) profile.copy(endpoint = endpoint) else profile

                val outcome = tryEndpoint(attempt, config, routes, withIpv6, viaBackup, last, note)
                when (outcome) {
                    Outcome.CONNECTED -> return
                    Outcome.GAVE_UP -> return
                    Outcome.NEXT_ENDPOINT -> Unit
                    is Outcome.BROKEN -> lastError = outcome.error
                }
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
            publish(
                TunnelStatus(
                    state = ConnectionState.CONNECTED,
                    connectedSince = System.currentTimeMillis(),
                    routeCount = appliedRoutes.size,
                    serverName = profile?.endpointHost.orEmpty(),
                )
            )
            startWatching()
        } else if (!up && _status.value.state == ConnectionState.CONNECTED) {
            watchJob?.cancel()
            watchJob = null
            publish(TunnelStatus())
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
        publish(TunnelStatus(state = ConnectionState.DISCONNECTED))
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
            publish(_status.value.copy(routeCount = routes.size))
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

        // Программы, которым VPN мешает жить: система не должна показывать
        // им туннель вовсе, иначе МАХ скажет «Отключите VPN».
        val apps = directApps()

        // Без своего DNS толку от туннеля мало: провайдер отвечает на
        // заблокированные имена подставным российским адресом, а тот идёт
        // мимо VPN — и сайт всё равно не открывается. Если в ключе DNS не
        // указан, подставляем публичный.
        var effective = if (profile.dns.isEmpty()) {
            profile.copy(dns = listOf("1.1.1.1", "8.8.8.8"))
        } else {
            profile
        }
        if (config.options.mtu > 0) {
            effective = effective.copy(mtu = config.options.mtu)
        }

        val text = effective.toConfigText(
            allowedIps = allowed,
            includeDns = config.options.useTunnelDns && config.effectiveMode != TunnelMode.INCLUDE,
            appsMode = if (apps.isEmpty()) AppsMode.OFF else AppsMode.EXCEPT_SELECTED,
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
                    nets + fittingRuZone()
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

    /**
     * Российская зона, ужатая до размера, который Android способен принять.
     *
     * Точный список даёт больше двадцати тысяч маршрутов: такую посылку
     * система не принимает — туннель молча не поднимается, значка VPN нет,
     * а приложение думает, что всё хорошо. Поэтому список укрупняется, пока
     * маршрутов не станет разумное количество. Сервисы, которые при этом
     * могли бы случайно уйти мимо туннеля, возвращаются обратно.
     */
    private fun fittingRuZone(): List<Ipv4Net> {
        cachedZone?.let { return it }

        val exact = RuZone.networks(context)
        if (exact.isEmpty()) return exact

        val keep = KeepInTunnel.nets()
        var zone = Cidr.subtract(exact, keep)
        var routes = Cidr.complement(zone).size
        var step = 0

        while (routes > MAX_ROUTES && step < GAPS.size) {
            zone = Cidr.subtract(Cidr.mergeWithGap(exact, GAPS[step]), keep)
            routes = Cidr.complement(zone).size
            step++
        }

        lastZoneRoutes = routes
        cachedZone = zone
        return zone
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
    /**
     * Что сейчас идёт мимо туннеля целиком — для экрана и отчёта.
     *
     * Человек должен видеть своими глазами, что МАХ в списке: иначе на
     * слово «исправлено» полагаться нечем.
     */
    fun directAppNames(): List<String> = directApps()

    private fun directApps(): List<String> {
        cachedDirectApps?.let { return it }

        val manager = context.packageManager
        val found = LinkedHashSet<String>()

        // Точные имена — проверяются напрямую: у предустановленных программ
        // может не быть значка на экране, и в списке запускаемых их не видно.
        for (name in DirectApps.packages) {
            if (name != context.packageName && isInstalled(manager, name)) found += name
        }

        // Остальное ищем среди установленных: по куску имени и по названию.
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val installed = try {
            manager.queryIntentActivities(intent, 0)
        } catch (error: Exception) {
            emptyList()
        }
        for (info in installed) {
            val name = info.activityInfo?.packageName ?: continue
            if (name == context.packageName || name in found) continue
            val label = runCatching { info.loadLabel(manager).toString() }.getOrDefault("")
            if (DirectApps.matches(name, label)) found += name
        }

        val result = found.toList()
        cachedDirectApps = result
        return result
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
        link.start(_status.value.rxBytes, _status.value.txBytes, System.currentTimeMillis())

        watchJob = scope.launch {
            while (isActive) {
                delay(2_000)

                // Одна выборка на круг: и счётчики, и время рукопожатия
                // берутся из неё же. Раньше их запрашивали по отдельности,
                // а каждый запрос дёргает движок туннеля.
                val statistics = try {
                    backend.getStatistics(tunnel)
                } catch (error: Exception) {
                    null
                } ?: continue

                val rx = statistics.totalRx()
                val tx = statistics.totalTx()
                val handshake = statistics.peers()
                    .maxOfOrNull { statistics.peer(it)?.latestHandshakeEpochMillis() ?: 0L } ?: 0L

                publish(_status.value.copy(rxBytes = rx, txBytes = tx, lastHandshake = handshake))

                if (link.stalled(rx, tx, System.currentTimeMillis())) {
                    publish(_status.value.copy(message = "Сервер молчит — переподключаюсь…"))
                    connect()
                    return@launch
                }
            }
        }
    }

    /** Чем кончилась попытка поднять туннель через один вход. */
    private sealed interface Outcome {
        /** Связь есть — больше ничего не нужно. */
        data object CONNECTED : Outcome

        /** Сервер не ответил, а других входов не осталось. */
        data object GAVE_UP : Outcome

        /** Сервер не ответил, но есть запасной вход. */
        data object NEXT_ENDPOINT : Outcome

        /** Туннель не поднялся вовсе — пробуем следующий набор маршрутов. */
        data class BROKEN(val error: Exception) : Outcome
    }

    /**
     * Одна попытка: поднять туннель к указанному входу и дождаться ответа.
     *
     * Первому входу даём меньше времени, когда есть запасной: лучше быстро
     * перебрать оба, чем двадцать секунд ждать молчащий.
     */
    private suspend fun tryEndpoint(
        profile: WgProfile,
        config: AppConfig,
        routes: List<String>,
        withIpv6: Boolean,
        viaBackup: Boolean,
        last: Boolean,
        note: String,
    ): Outcome {
        try {
            applyConfig(profile, config, routes, withIpv6 = withIpv6)
        } catch (error: Exception) {
            return Outcome.BROKEN(error)
        }

        appliedRoutes = routes
        publish(
            TunnelStatus(
                state = ConnectionState.CONNECTING,
                routeCount = routes.size,
                serverName = profile.endpointHost,
                message = if (viaBackup) "Пробую запасной вход…" else "Устанавливаю связь с сервером…",
            )
        )

        // Поднятый туннель — ещё не связь. Пока сервер не ответил на
        // рукопожатие, трафик уходит в пустоту, а телефон при этом уже
        // считает, что VPN работает: интернета нет, и непонятно почему.
        if (!awaitHandshake(if (last) 20_000 else 12_000)) {
            takeDown()
            // Есть запасной вход — молча пробуем его: человеку важен
            // результат, а не то, каким путём он получен.
            if (!last) return Outcome.NEXT_ENDPOINT
            fail(failureText(profile.endpointHost, viaBackup))
            return Outcome.GAVE_UP
        }

        usedBackupEntry = viaBackup

        // Связь есть — но «есть» ещё не значит «работает». Проверяем, что
        // проходят большие порции данных, и если нет — уменьшаем пакет.
        if (config.options.mtu == 0) {
            tuneMtu(profile, config, routes, withIpv6)
        }

        publish(
            TunnelStatus(
                state = ConnectionState.CONNECTED,
                connectedSince = System.currentTimeMillis(),
                routeCount = routes.size,
                serverName = profile.endpointHost,
                message = if (viaBackup) "Через запасной вход" else note,
                lastHandshake = lastHandshakeMillis(),
            )
        )
        startWatching()
        return Outcome.CONNECTED
    }

    /**
     * Подбирает размер пакета, пока не пойдут большие порции данных.
     *
     * Симптом неподходящего размера узнаваемый: сообщения отправляются,
     * а видео крутится и не скачивается, потоковый ответ обрывается на
     * середине. Мелкое пролезает, крупное — нет.
     *
     * Начинаем с того, что подошло в прошлый раз: сеть обычно та же, и
     * перебирать заново незачем.
     */
    private suspend fun tuneMtu(
        profile: WgProfile,
        config: AppConfig,
        routes: List<String>,
        withIpv6: Boolean,
    ) {
        val remembered = config.options.probedMtu
        val start = if (remembered > 0) remembered else profile.mtu.coerceAtMost(MTU_LADDER.first())
        val ladder = (listOf(start) + MTU_LADDER.filter { it < start }).distinct()

        // Туннель уже поднят с размером из ключа: если начинаем с другого,
        // его надо применить, иначе проверим не то, что думаем.
        var applied = profile.mtu

        for (mtu in ladder) {
            if (mtu != applied) {
                publish(_status.value.copy(message = "Подбираю размер пакета: $mtu…"))
                try {
                    applyConfig(profile.copy(mtu = mtu), config, routes, withIpv6 = withIpv6)
                } catch (error: Exception) {
                    return
                }
                applied = mtu
                if (!awaitHandshake(10_000)) continue
            }

            if (BulkCheck.works()) {
                activeMtu = mtu
                if (mtu != remembered) {
                    store.update { it.copy(options = it.options.copy(probedMtu = mtu)) }
                }
                return
            }
        }

        // Ни один размер не помог — значит, дело не в нём. Остаёмся на
        // нижней ступени: она хотя бы заведомо проходит.
        activeMtu = ladder.last()
    }

    /** С каким размером пакета туннель сейчас работает. */
    @Volatile
    var activeMtu: Int = 0
        private set

    /** Куда подключились в итоге — видно в отчёте диагностики. */
    @Volatile
    var usedBackupEntry: Boolean = false
        private set

    private fun failureText(host: String, viaBackup: Boolean): String = buildString {
        append(if (viaBackup) "Запасной вход $host тоже молчит. " else "Сервер $host не ответил. ")
        append(
            "Обычно это значит одно из трёх: ключ выдан для другого протокола " +
                "(нужен AmneziaWG или WireGuard), сервер недоступен, или эта сеть не выпускает " +
                "наружу ничего, кроме разрешённых адресов — так бывает при отключении " +
                "мобильного интернета, и тогда помогает только Wi-Fi."
        )
    }

    private fun fail(message: String) {
        publish(TunnelStatus(state = ConnectionState.ERROR, message = message))
    }
}
