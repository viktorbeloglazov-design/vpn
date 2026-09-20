package kz.qpvpn

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kz.qpvpn.model.MasterFilter
import kz.qpvpn.model.ConnectionState
import kz.qpvpn.model.TunnelOptions
import kz.qpvpn.net.IpCheck
import kz.qpvpn.net.SpeedTest
import kz.qpvpn.net.RuZone
import kz.qpvpn.ui.Format
import kz.qpvpn.ui.QrScannerScreen
import kz.qpvpn.ui.decodeQrFromImage
import kz.qpvpn.ui.QpVpnTheme
import kz.qpvpn.ui.ScreenActions
import kz.qpvpn.ui.ScreenState
import kz.qpvpn.vpn.AmneziaLink
import kz.qpvpn.vpn.WgProfile

class MainActivity : ComponentActivity() {

    private val app: QpVpnApp by lazy { application as QpVpnApp }

    private var profileVersion by mutableStateOf(0)
    private var ipText by mutableStateOf("")
    private var ipIsKazakhstan by mutableStateOf(false)
    private var checkingIp by mutableStateOf(false)
    private var ruZoneCount by mutableStateOf(0)
    private var directApps by mutableStateOf<List<String>>(emptyList())
    private var speedText by mutableStateOf("")
    private var speedHint by mutableStateOf("")
    private var measuringSpeed by mutableStateOf(false)
    private var notificationsAllowed by mutableStateOf(true)
    private var showScanner by mutableStateOf(false)

    /** Системное окно «разрешить VPN» — без него туннель поднять нельзя. */
    private val vpnConsent = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == RESULT_OK) {
            startTunnel()
        } else {
            app.store.update { it.copy(enabled = false) }
        }
    }

    private val pickProfile = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri != null) importProfile(uri)
    }

    /** Снимок экрана с QR-кодом: Amnezia на этом же телефоне не отсканировать. */
    private val pickQrImage = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        if (uri == null) return@registerForActivityResult
        lifecycleScope.launch {
            val text = withContext(Dispatchers.IO) { decodeQrFromImage(this@MainActivity, uri) }
            if (text.isNullOrBlank()) {
                showProfileError("На картинке не нашёлся QR-код.")
            } else {
                importFromText(text)
            }
        }
    }

    private val askNotifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        notificationsAllowed = granted
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Без разрешения на уведомления телефон не покажет значок VPN наверху:
        // спрашиваем сразу, а отказ подсвечиваем на главном экране.
        notificationsAllowed = hasNotificationPermission()
        if (!notificationsAllowed) {
            askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        handleSharedIntent(intent)

        // Туннель мог остаться поднятым с прошлого запуска: сверяем, что
        // показано на экране, с тем, что на самом деле держит система.
        lifecycleScope.launch { app.tunnel.syncState() }

        setContent {
            QpVpnTheme {
                val config by app.store.config.collectAsStateWithLifecycle()
                val status by app.tunnel.status.collectAsStateWithLifecycle()

                LaunchedEffect(Unit) {
                    ruZoneCount = withContext(Dispatchers.IO) { RuZone.count(this@MainActivity) }
                    directApps = withContext(Dispatchers.IO) { directAppLabels() }
                }

                val profileSummary = remember(profileVersion) { summarizeProfile() }
                val profileProtocol = remember(profileVersion) { profileProtocol() }
                val hasProfile = remember(profileVersion) { app.store.hasProfile }

                if (showScanner) {
                    QrScannerScreen(
                        onResult = { text ->
                            showScanner = false
                            importFromText(text)
                        },
                        onClose = { showScanner = false },
                    )
                    return@QpVpnTheme
                }

                kz.qpvpn.ui.QpVpnRoot(
                    state = ScreenState(
                        config = config,
                        status = status,
                        hasProfile = hasProfile,
                        profileSummary = profileSummary,
                        profileProtocol = profileProtocol,
                        ruZoneCount = ruZoneCount,
                        directApps = directApps,
                        masterCount = MasterFilter.count,
                        masterSections = MasterFilter.sections.map { it.title to it.domains.size },
                        notificationsAllowed = notificationsAllowed,
                        diagnostics = { diagnostics(status) },
                        ipText = ipText,
                        ipIsKazakhstan = ipIsKazakhstan,
                        checkingIp = checkingIp,
                        speedText = speedText,
                        speedHint = speedHint,
                        measuringSpeed = measuringSpeed,
                    ),
                    actions = ScreenActions(
                        onToggle = ::toggleTunnel,
                        onWorkFilterChange = ::changeWorkFilter,
                        onOpenNotificationSettings = ::openNotificationSettings,
                        onPickProfile = { pickProfile.launch(arrayOf("*/*")) },
                        onClearProfile = ::clearProfile,
                        onOptionsChange = ::changeOptions,
                        onCheckIp = ::checkIp,
                        onMeasureSpeed = ::measureSpeed,
                        onCopyDiagnostics = ::copyDiagnostics,
                        onScanQr = { showScanner = true },
                        onPickQrImage = { pickQrImage.launch("image/*") },
                        onImportText = ::importFromText,
                    ),
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        notificationsAllowed = hasNotificationPermission()
        lifecycleScope.launch { app.tunnel.syncState() }
    }

    /**
     * Названия программ, которые идут мимо VPN, — их показываем на экране.
     *
     * Имя пакета человеку ничего не говорит: он должен увидеть «МАХ».
     */
    private fun directAppLabels(): List<String> {
        val manager = packageManager
        val labels = app.tunnel.directAppNames().map { name ->
            name to runCatching {
                manager.getApplicationLabel(manager.getApplicationInfo(name, 0)).toString()
            }.getOrDefault(name)
        }
        // МАХ впереди: ради него всё и затевалось, его и должно быть видно.
        return labels
            .sortedBy { (name, label) ->
                if (name.contains("oneme") || label.equals("max", ignoreCase = true)) "" else label.lowercase()
            }
            .map { it.second }
    }

    private fun hasNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** Открывает системные настройки уведомлений программы. */
    private fun openNotificationSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
        ) {
            askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
            return
        }
        val intent = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
        runCatching { startActivity(intent) }.onFailure {
            askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    // MARK: - Туннель

    private fun toggleTunnel() {
        val state = app.tunnel.status.value.state
        if (state == ConnectionState.CONNECTED || state == ConnectionState.CONNECTING) {
            lifecycleScope.launch {
                app.tunnel.disconnect()
                app.store.update { it.copy(enabled = false) }
            }
            return
        }

        val intent: Intent? = VpnService.prepare(this)
        if (intent != null) {
            vpnConsent.launch(intent)
        } else {
            startTunnel()
        }
    }

    private fun startTunnel() {
        lifecycleScope.launch {
            app.store.update { it.copy(enabled = true) }
            app.tunnel.connect()
        }
    }

    // MARK: - Рабочие ресурсы

    /**
     * Единственная настройка маршрутизации, которая осталась у человека.
     *
     * Всё остальное зашито в программу: заблокированные сервисы идут через
     * VPN, российские адреса — напрямую, менять это негде и не нужно.
     */
    private fun changeWorkFilter(enabled: Boolean) {
        app.store.update { it.copy(workFilter = enabled) }
        lifecycleScope.launch { app.tunnel.refreshRoutes() }
    }

    /**
     * Размер пакета задаётся при подключении, поэтому туннель пересоздаётся.
     *
     * Иначе человек выбирает другое число, ничего не меняется, и он решает,
     * что настройка не работает.
     */
    private fun changeOptions(options: TunnelOptions) {
        val was = app.store.config.value.options
        app.store.update { it.copy(options = options) }
        if (was.mtu == options.mtu) return
        if (app.tunnel.status.value.state != ConnectionState.CONNECTED) return
        lifecycleScope.launch {
            app.tunnel.disconnect()
            app.tunnel.connect()
        }
    }

    // MARK: - Профиль

    /** Приём того, чем поделились: ссылка vpn://, текст настроек или файл. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSharedIntent(intent)
    }

    private fun handleSharedIntent(intent: Intent?) {
        if (intent == null) return

        val fromLink = intent.data?.toString()
        val fromText = intent.getStringExtra(Intent.EXTRA_TEXT)
        val fromFile = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }

        when {
            !fromLink.isNullOrBlank() && fromLink.startsWith("vpn://") -> importFromText(fromLink)
            !fromText.isNullOrBlank() -> importFromText(fromText)
            fromFile != null -> importProfile(fromFile)
            intent.action == Intent.ACTION_VIEW && intent.data != null -> importProfile(intent.data!!)
        }
    }

    /** Общий путь для ссылки, QR-кода и вставленного текста. */
    private fun importFromText(text: String) {
        val config = AmneziaLink.extractConfig(text)
        if (config == null) {
            val protocol = AmneziaLink.describeProtocol(text)
            showProfileError(
                if (protocol != null) {
                    "В ссылке протокол $protocol. Программа поднимает туннель только " +
                        "по WireGuard и AmneziaWG — в Amnezia выберите один из них при экспорте."
                } else {
                    "В этом тексте нет настроек WireGuard или AmneziaWG."
                }
            )
            return
        }
        try {
            val profile = WgProfile.parse(config)
            app.store.saveProfile(config)
            profileVersion++
            val kind = if (profile.isAmnezia) "AmneziaWG" else "WireGuard"
            android.widget.Toast.makeText(
                this,
                "Профиль $kind загружен: ${profile.endpointHost}",
                android.widget.Toast.LENGTH_LONG,
            ).show()
        } catch (error: Exception) {
            showProfileError(error.message ?: "Настройки не подошли.")
        }
    }

    private fun importProfile(uri: Uri) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val raw = contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                        ?: throw IllegalStateException("Файл не открылся.")
                    val text = AmneziaLink.extractConfig(raw)
                        ?: throw IllegalStateException("В файле нет настроек WireGuard.")
                    WgProfile.parse(text)
                    text
                }
            }

            result.onSuccess { text ->
                app.store.saveProfile(text)
                profileVersion++
            }.onFailure { error ->
                showProfileError(error.message ?: "Файл не подошёл.")
            }
        }
    }

    private fun showProfileError(message: String) {
        android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_LONG).show()
    }

    private fun clearProfile() {
        lifecycleScope.launch {
            app.tunnel.disconnect()
            app.store.clearProfile()
            app.store.update { it.copy(enabled = false) }
            profileVersion++
        }
    }

    /** Название протокола для шапки: обычный WireGuard или маскированный AmneziaWG. */
    /**
     * Короткий отчёт о состоянии — его можно переслать тому, кто выдал ключ.
     *
     * Ключей внутри нет: только адрес сервера, режим, счётчики и время
     * последнего ответа сервера. Этого хватает, чтобы понять, где встало.
     */
    private fun diagnostics(status: kz.qpvpn.model.TunnelStatus): String {
        val config = app.store.config.value
        val profile = app.store.profileText()?.let { text ->
            runCatching { WgProfile.parse(text) }.getOrNull()
        }

        val handshake = if (status.lastHandshake > 0) {
            val seconds = (System.currentTimeMillis() - status.lastHandshake) / 1000
            "$seconds с назад"
        } else {
            "не было"
        }

        val mode = "обход блокировок (всё, кроме ${RuZone.count(this)} подсетей РФ)"

        return buildString {
            appendLine("QP VPN ${BuildConfig.VERSION_NAME}, Android ${android.os.Build.VERSION.RELEASE}, ${android.os.Build.MODEL}")
            appendLine("Состояние: ${status.state.title}${if (status.message.isNotEmpty()) " — ${status.message}" else ""}")
            appendLine("Сеть: ${networkKind()}")
            appendLine("Режим: $mode")
            appendLine("Рабочие ресурсы: ${if (config.workFilter) "через VPN" else "напрямую"}")
            val direct = app.tunnel.directAppNames()
            appendLine("Мимо VPN целиком: ${if (direct.isEmpty()) "нет таких программ" else direct.joinToString(", ")}")
            if (profile != null) {
                appendLine("Сервер: ${profile.endpoint}")
                appendLine("Протокол: ${profile.protocolName}, параметров маскировки: ${profile.amneziaParams.size}")
                appendLine("DNS из ключа: ${profile.dns.joinToString(", ").ifEmpty { "нет, подставляем 1.1.1.1" }}")
                appendLine("MTU: ${if (config.options.mtu > 0) "${config.options.mtu} (задан вручную)" else "${profile.mtu} (из ключа)"}")
            } else {
                appendLine("Ключ: не загружен")
            }
            appendLine("Маршрутов в туннеле: ${status.routeCount}")
            appendLine("Рукопожатие: $handshake")
            append("Принято/отправлено: ${Format.bytes(status.rxBytes)} / ${Format.bytes(status.txBytes)}")
        }
    }

    /** Через что телефон сейчас в интернете. */
    private fun networkKind(): String {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return "неизвестно"
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return "нет сети"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "мобильная"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "провод"
            else -> "другая"
        }
    }

    private fun copyDiagnostics() {
        val manager = getSystemService(ClipboardManager::class.java) ?: return
        manager.setPrimaryClip(
            ClipData.newPlainText("QP VPN", diagnostics(app.tunnel.status.value))
        )
        Toast.makeText(this, "Отчёт скопирован", Toast.LENGTH_SHORT).show()
    }

    private fun profileProtocol(): String {
        val text = app.store.profileText() ?: return ""
        return runCatching { WgProfile.parse(text).protocolName }.getOrDefault("WireGuard")
    }

    private fun summarizeProfile(): String {
        val text = app.store.profileText() ?: return ""
        return try {
            val profile = WgProfile.parse(text)
            buildString {
                if (profile.isAmnezia) {
                    append("протокол AmneziaWG, параметров маскировки: ${profile.amneziaParams.size}\n")
                } else {
                    append("протокол WireGuard без маскировки\n")
                }
                append("сервер ${profile.endpoint}")
                append("\nадрес ${profile.addresses.joinToString(", ")}")
                if (profile.dns.isNotEmpty()) append("\nDNS ${profile.dns.joinToString(", ")}")
                append("\nMTU ${profile.mtu}")
            }
        } catch (error: Exception) {
            error.message ?: "Профиль повреждён."
        }
    }

    // MARK: - Прочее

    /**
     * Замер скорости двумя путями сразу.
     *
     * Одно число ничего не говорит: в кафе Wi-Fi бывает медленнее любого
     * VPN. Сравнение с прямой закачкой отвечает, виноват туннель или сеть.
     */
    private fun measureSpeed() {
        if (measuringSpeed) return
        measuringSpeed = true
        speedText = ""
        speedHint = ""
        lifecycleScope.launch {
            val result = SpeedTest.measure(this@MainActivity)
            measuringSpeed = false
            speedText = if (result.hasAny) {
                "через VPN ${SpeedTest.format(result.throughTunnel)}  ·  " +
                    "без VPN ${SpeedTest.format(result.direct)}"
            } else {
                ""
            }
            speedHint = when {
                result.note.isNotEmpty() -> result.note
                result.tunnelIsSlower ->
                    "Туннель заметно медленнее прямой закачки. Попробуйте «Ещё» → MTU → 1420, " +
                        "а если не поможет — дело в сервере или в этой сети."
                result.throughTunnel > 0 && result.direct > 0 ->
                    "Туннель не режет скорость — она такая же, как без него. Значит, упирается сама сеть."
                else -> ""
            }
        }
    }

    private fun checkIp() {
        if (checkingIp) return
        checkingIp = true
        lifecycleScope.launch {
            val result = IpCheck.fetch()
            checkingIp = false
            result.onSuccess { info ->
                ipText = info.summary
                ipIsKazakhstan = info.isKazakhstan
            }.onFailure { error ->
                val message = error.message.orEmpty()
                // Когда весь трафик уходит в неработающий туннель, телефон
                // теряет даже DNS — «unable to resolve host» означает именно
                // это, а не поломку проверки.
                ipText = if (message.contains("resolve host", ignoreCase = true) ||
                    message.contains("Unable to resolve", ignoreCase = true)
                ) {
                    "Интернета нет: имена сайтов не разрешаются. Если туннель включён — выключите его кнопкой; " +
                        "похоже, сервер не отвечает."
                } else {
                    "Не удалось проверить адрес: $message"
                }
                ipIsKazakhstan = false
            }
        }
    }
}
