package kz.qpvpn

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kz.qpvpn.model.AppsMode
import kz.qpvpn.model.MasterFilter
import kz.qpvpn.model.ConnectionState
import kz.qpvpn.model.RoutingRule
import kz.qpvpn.model.RuleKind
import kz.qpvpn.model.RulePreset
import kz.qpvpn.model.TunnelMode
import kz.qpvpn.model.TunnelOptions
import kz.qpvpn.net.Cidr
import kz.qpvpn.net.IpCheck
import kz.qpvpn.net.RuZone
import kz.qpvpn.ui.AppEntry
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
    private var installedApps by mutableStateOf<List<AppEntry>>(emptyList())
    private var ruZoneCount by mutableStateOf(0)
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

    private val askNotifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        handleSharedIntent(intent)

        setContent {
            QpVpnTheme {
                val config by app.store.config.collectAsStateWithLifecycle()
                val status by app.tunnel.status.collectAsStateWithLifecycle()

                LaunchedEffect(Unit) {
                    installedApps = loadInstalledApps()
                }

                LaunchedEffect(Unit) {
                    ruZoneCount = withContext(Dispatchers.IO) { RuZone.count(this@MainActivity) }
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
                        apps = installedApps,
                        ruZoneCount = ruZoneCount,
                        masterCount = MasterFilter.count,
                        masterSections = MasterFilter.sections.map { it.title to it.domains.size },
                        masterApps = MasterFilter.packageCount,
                        ipText = ipText,
                        ipIsKazakhstan = ipIsKazakhstan,
                        checkingIp = checkingIp,
                    ),
                    actions = ScreenActions(
                        onToggle = ::toggleTunnel,
                        onModeChange = ::changeMode,
                        onMainFilterChange = ::changeMainFilter,
                        onWorkFilterChange = ::changeWorkFilter,
                        onAddRule = ::addRule,
                        onToggleRule = ::toggleRule,
                        onDeleteRule = ::deleteRule,
                        onAddPreset = ::addPreset,
                        onAppsModeChange = ::changeAppsMode,
                        onToggleApp = ::toggleApp,
                        onPickProfile = { pickProfile.launch(arrayOf("*/*")) },
                        onClearProfile = ::clearProfile,
                        onOptionsChange = ::changeOptions,
                        onCheckIp = ::checkIp,
                        onScanQr = { showScanner = true },
                        onPickQrImage = { pickQrImage.launch("image/*") },
                        onImportText = ::importFromText,
                    ),
                )
            }
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

    // MARK: - Правила

    /** Главный фильтр сам задаёт маршруты, поэтому туннель пересобирается. */
    private fun changeMainFilter(enabled: Boolean) {
        app.store.update { it.copy(mainFilter = enabled) }
        reapplyRoutes()
    }

    /** Рабочие ресурсы: включён — через VPN, выключен — напрямую. */
    private fun changeWorkFilter(enabled: Boolean) {
        app.store.update { it.copy(workFilter = enabled) }
        reapplyRoutes()
    }

    private fun changeMode(mode: TunnelMode) {
        app.store.update { it.copy(mode = mode) }
        reapplyRoutes()
    }

    private fun addRule(kind: RuleKind, value: String): String? {
        val text = value.trim().lowercase()
        Cidr.ruleError(kind, text)?.let { return it }
        if (app.store.config.value.rules.any { it.kind == kind && it.value.equals(text, ignoreCase = true) }) {
            return "Такое правило уже есть."
        }
        app.store.update { it.copy(rules = it.rules + RoutingRule(kind = kind, value = text)) }
        reapplyRoutes()
        return null
    }

    private fun toggleRule(id: String, enabled: Boolean) {
        app.store.update { config ->
            config.copy(rules = config.rules.map { if (it.id == id) it.copy(enabled = enabled) else it })
        }
        reapplyRoutes()
    }

    private fun deleteRule(id: String) {
        app.store.update { config -> config.copy(rules = config.rules.filterNot { it.id == id }) }
        reapplyRoutes()
    }

    private fun addPreset(preset: RulePreset) {
        app.store.update { config ->
            val existing = config.rules.map { "${it.kind}:${it.value.lowercase()}" }.toSet()
            val added = preset.rules().filterNot { "${it.kind}:${it.value.lowercase()}" in existing }
            // Набор бессмысленен в режиме «весь трафик»: переводим в тот режим,
            // ради которого его и добавляют.
            val mode = if (config.mode == TunnelMode.FULL) preset.direction.mode else config.mode
            config.copy(rules = config.rules + added, mode = mode)
        }
        reapplyRoutes()
    }

    private fun changeAppsMode(mode: AppsMode) {
        app.store.update { it.copy(appsMode = mode) }
        restartIfRunning()
    }

    private fun toggleApp(packageName: String, selected: Boolean) {
        app.store.update { config ->
            val apps = if (selected) config.selectedApps + packageName
            else config.selectedApps - packageName
            config.copy(selectedApps = apps.distinct())
        }
        restartIfRunning()
    }

    private fun changeOptions(options: TunnelOptions) {
        app.store.update { it.copy(options = options) }
    }

    private fun reapplyRoutes() {
        lifecycleScope.launch { app.tunnel.refreshRoutes() }
    }

    /** Списки программ применяются только при пересоздании туннеля. */
    private fun restartIfRunning() {
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
                    append("протокол AmneziaWG — обычный WireGuard-сервер его не примет\n")
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

    private fun checkIp() {
        if (checkingIp) return
        checkingIp = true
        lifecycleScope.launch {
            val result = IpCheck.fetch()
            checkingIp = false
            result.onSuccess { info ->
                ipText = info.summary
                ipIsKazakhstan = info.isKazakhstan
            }.onFailure {
                ipText = "Не удалось проверить адрес: ${it.message}"
                ipIsKazakhstan = false
            }
        }
    }

    private suspend fun loadInstalledApps(): List<AppEntry> = withContext(Dispatchers.IO) {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val manager = packageManager
        manager.queryIntentActivities(intent, 0)
            .asSequence()
            .mapNotNull { info ->
                val packageName = info.activityInfo?.packageName ?: return@mapNotNull null
                if (packageName == getPackageName()) return@mapNotNull null
                val icon = runCatching { info.loadIcon(manager).toImageBitmap() }.getOrNull()
                AppEntry(packageName, info.loadLabel(manager).toString(), icon)
            }
            .distinctBy { it.packageName }
            .sortedBy { it.label.lowercase() }
            .toList()
    }

    /** Значок программы приходит рисунком системы — переводим его в картинку Compose. */
    private fun Drawable.toImageBitmap(size: Int = 96): ImageBitmap {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        setBounds(0, 0, size, size)
        draw(canvas)
        return bitmap.asImageBitmap()
    }
}
