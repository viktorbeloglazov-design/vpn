package kz.carlink

import android.Manifest
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings as AndroidSettings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import kz.carlink.diag.EventLog
import kz.carlink.projection.ProjectionMode
import kz.carlink.projection.TouchInjector
import kz.carlink.ui.CarLinkScreen
import kz.carlink.usb.AoapTransport

class MainActivity : ComponentActivity() {

    private var accessory by mutableStateOf<String?>(null)
    private var mode by mutableStateOf(ProjectionMode.CAR_UI)
    private var hasCredentials by mutableStateOf(false)
    private var pendingCredentials by mutableStateOf<ByteArray?>(null)

    private val captureLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == RESULT_OK && result.data != null) {
            CarLinkService.start(this, result.resultCode, result.data)
        } else {
            EventLog.log("показ экрана не разрешён — без него зеркало и звук работать не будут")
        }
    }

    private val permissionLauncher = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        result.filterValues { !it }.keys.forEach { EventLog.log("разрешение не выдано: $it") }
    }

    private val credentialsLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@registerForActivityResult
        val data = runCatching { contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()
        if (data == null) {
            EventLog.log("не смог прочитать файл ключа")
        } else {
            pendingCredentials = data
        }
    }

    private val usbEvents = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_ACCESSORY_DETACHED -> {
                    EventLog.log("провод вынули")
                    CarLinkService.stop(this@MainActivity)
                    refresh()
                }
                AoapTransport.PERMISSION_ACTION -> {
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    EventLog.log(if (granted) "доступ к машине разрешён" else "доступ к машине запрещён")
                    refresh()
                    if (granted) connect()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        mode = Settings.mode(this)
        hasCredentials = Settings.hasCredentials(this)
        requestPermissions()

        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_ACCESSORY_DETACHED)
            addAction(AoapTransport.PERMISSION_ACTION)
        }
        ContextCompat.registerReceiver(this, usbEvents, filter, ContextCompat.RECEIVER_NOT_EXPORTED)

        setContent {
            val state by CarLinkService.status.collectAsState()
            val log by EventLog.lines.collectAsState()
            CarLinkScreen(
                state = state,
                accessory = accessory,
                mode = mode,
                hasCredentials = hasCredentials,
                injectorEnabled = TouchInjector.instance != null,
                log = log,
                passwordRequested = pendingCredentials != null,
                onModeChange = {
                    mode = it
                    Settings.setMode(this, it)
                },
                onConnect = ::connect,
                onDisconnect = { CarLinkService.stop(this) },
                onPickCredentials = { credentialsLauncher.launch(arrayOf("*/*")) },
                onForgetCredentials = {
                    Settings.forgetCredentials(this)
                    hasCredentials = false
                    EventLog.log("ключ удалён, вернулся отладочный")
                },
                onPasswordEntered = ::saveCredentials,
                onPasswordCancelled = { pendingCredentials = null },
                onOpenAccessibility = {
                    startActivity(Intent(AndroidSettings.ACTION_ACCESSIBILITY_SETTINGS))
                },
                onCopyLog = {
                    val clipboard = getSystemService(ClipboardManager::class.java)
                    clipboard.setPrimaryClip(ClipData.newPlainText("CarLink", EventLog.asText()))
                },
                onClearLog = EventLog::clear,
            )
        }

        handleAttachIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleAttachIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(usbEvents) }
        super.onDestroy()
    }

    private fun handleAttachIntent(intent: Intent?) {
        if (intent?.action != UsbManager.ACTION_USB_ACCESSORY_ATTACHED) return
        refresh()
        EventLog.log("машина позвала приложение сама")
        // В режиме своего экрана разрешение на показ не нужно — можно
        // подключаться сразу, не дожидаясь нажатия.
        if (Settings.mode(this) == ProjectionMode.CAR_UI) connect()
    }

    /** Уведомление службы и звук телефона в машину — оба под разрешением. */
    private fun requestPermissions() {
        val needed = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
            add(Manifest.permission.RECORD_AUDIO)
        }.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isNotEmpty()) permissionLauncher.launch(needed.toTypedArray())
    }

    private fun refresh() {
        val attached = AoapTransport.attached(this)
        accessory = attached?.let { AoapTransport.describe(it) }
        hasCredentials = Settings.hasCredentials(this)
    }

    private fun connect() {
        val attached = AoapTransport.attached(this)
        if (attached == null) {
            EventLog.log("провод не найден: телефон должен быть в порту USB машины")
            return
        }
        if (!AoapTransport.hasPermission(this, attached)) {
            AoapTransport.requestPermission(this, attached)
            return
        }
        if (mode == ProjectionMode.MIRROR) {
            val manager = getSystemService(MediaProjectionManager::class.java)
            captureLauncher.launch(manager.createScreenCaptureIntent())
        } else {
            CarLinkService.start(this, 0, null)
        }
    }

    private fun saveCredentials(password: String) {
        val data = pendingCredentials ?: return
        pendingCredentials = null
        try {
            Settings.saveCredentials(this, data, password)
            hasCredentials = true
            EventLog.log("ключ принят")
        } catch (e: Exception) {
            EventLog.log("ключ не подошёл: ${e.message}")
        }
    }
}
