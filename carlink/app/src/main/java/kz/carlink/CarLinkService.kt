package kz.carlink

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kz.carlink.aa.FrameCodec
import kz.carlink.aa.Session
import kz.carlink.aa.Stage
import kz.carlink.diag.EventLog
import kz.carlink.net.LocalAddresses
import kz.carlink.net.TcpListener
import kz.carlink.net.TcpTransport
import kz.carlink.projection.PlaybackCapture
import kz.carlink.projection.ProjectionMode
import kz.carlink.projection.ScreenProjection
import kz.carlink.usb.AoapTransport
import java.io.InputStream
import java.io.OutputStream
import javax.net.ssl.KeyManager

/** Что показывает главный экран, пока идёт разговор с машиной. */
data class LinkState(
    val stage: Stage = Stage.WAITING,
    val detail: String = "",
    val running: Boolean = false,
)

/**
 * Служба, которая держит соединение.
 *
 * Живёт на переднем плане: провод — «подключённое устройство», а захват экрана
 * система разрешает только видимой службе. Соединение поднимается в рабочем
 * потоке — и потому, что открытие сокета с главного потока Android запрещает, и
 * потому, что чтение с провода блокирующее.
 */
class CarLinkService : Service() {

    private var session: Session? = null
    private var worker: Thread? = null
    private var projection: MediaProjection? = null
    private var closeLink: (() -> Unit)? = null
    private var listener: TcpListener? = null

    @Volatile
    private var keepWaiting = true

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                disconnect()
                stopSelf()
            }
            else -> connect(intent)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        disconnect()
        super.onDestroy()
    }

    private fun connect(intent: Intent?) {
        if (worker != null) {
            EventLog.log("соединение уже идёт")
            return
        }

        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, 0) ?: 0
        @Suppress("DEPRECATION")
        val resultData: Intent? = intent?.getParcelableExtra(EXTRA_RESULT_DATA)
        val withCapture = resultCode != 0 && resultData != null

        // Тип службы объявляем по факту: заявить захват экрана, не имея на него
        // разрешения, система не даёт — служба просто не запустится.
        goForeground(withCapture)

        if (withCapture) {
            val manager = getSystemService(MediaProjectionManager::class.java)
            projection = manager.getMediaProjection(resultCode, resultData!!)?.also {
                it.registerCallback(object : MediaProjection.Callback() {
                    override fun onStop() {
                        EventLog.log("захват экрана остановлен системой")
                    }
                }, Handler(Looper.getMainLooper()))
            }
        }

        val transport = Settings.transport(this)
        if (transport == Transport.USB && !usbReady()) {
            stopSelf()
            return
        }

        val keyManagers = try {
            Settings.keyManagers(this)
        } catch (e: Exception) {
            EventLog.log("не смог прочитать ключ: ${e.message}")
            stopSelf()
            return
        }
        if (!Settings.hasCredentials(this) && transport != Transport.DESK) {
            EventLog.log(
                "внимание: используется отладочный самоподписанный ключ. " +
                    "Серийная машина обрывает соединение сразу после рукопожатия — " +
                    "подробности в README."
            )
        }

        val mode = Settings.mode(this)
        val host = Settings.deskHost(this)
        val port = Settings.deskPort(this)

        keepWaiting = true
        worker = Thread({
            if (transport == Transport.WIFI) {
                waitForConnections(port, keyManagers, mode)
            } else {
                openLink(transport, host, port)?.let { runSession(it, keyManagers, mode) }
            }
            mainHandler.post {
                disconnect()
                stopSelf()
            }
        }, "carlink-session").also { it.start() }
    }

    /**
     * Режим ожидания: телефон держит порт и принимает подключения одно за
     * другим. Так работает беспроводной Android Auto — машина подключается
     * к телефону сама.
     */
    private fun waitForConnections(port: Int, keyManagers: Array<KeyManager>, mode: ProjectionMode) {
        val listener = try {
            TcpListener(port).also { this.listener = it }
        } catch (e: Exception) {
            EventLog.log("не смог занять порт $port: ${e.message}")
            return
        }
        val addresses = LocalAddresses.list()
        EventLog.log(
            if (addresses.isEmpty()) "жду подключение на порту $port"
            else "жду подключение на порту $port, адреса телефона: ${addresses.joinToString(", ")}"
        )
        update(Stage.WAITING, "жду подключение на порту $port")

        while (keepWaiting) {
            val link = try {
                listener.accept()
            } catch (e: Exception) {
                if (keepWaiting) EventLog.log("ожидание прервано: ${e.message}")
                break
            }
            closeLink = link::close
            EventLog.log("к телефону подключились")
            runSession(link.input to link.output, keyManagers, mode)
            closeLink = null
            if (!keepWaiting) break
            update(Stage.WAITING, "жду подключение на порту $port")
            EventLog.log("снова жду подключение на порту $port")
        }
        listener.close()
        this.listener = null
    }

    private fun runSession(
        streams: Pair<InputStream, OutputStream>,
        keyManagers: Array<KeyManager>,
        mode: ProjectionMode,
    ) {
        val screen = ScreenProjection(applicationContext, mode, { projection }, EventLog::log)
        val audio = if (projection != null) PlaybackCapture({ projection }, EventLog::log) else null
        val session = Session(
            codec = FrameCodec(streams.first, streams.second),
            keyManagers = keyManagers,
            projection = screen,
            audio = audio,
            deviceName = Build.MODEL ?: "Android",
            deviceBrand = Build.MANUFACTURER ?: "Android",
            log = EventLog::log,
            onStage = { stage, detail -> update(stage, detail) },
        )
        this.session = session
        session.run()
        this.session = null
        EventLog.log(session.statistics())
    }

    /** Открывает провод или соединение со стендом. */
    private fun openLink(transport: Transport, host: String, port: Int): Pair<InputStream, OutputStream>? =
        when (transport) {
            Transport.USB -> {
                val accessory = AoapTransport.attached(this)
                if (accessory == null) {
                    EventLog.log("машина отключилась, пока собирались")
                    null
                } else {
                    try {
                        val link = AoapTransport.open(this, accessory)
                        closeLink = link::close
                        link.input to link.output
                    } catch (e: Exception) {
                        EventLog.log("не открыл соединение с машиной: ${e.message}")
                        null
                    }
                }
            }

            Transport.WIFI -> null

            Transport.DESK -> try {
                EventLog.log("подключаюсь к стенду $host:$port")
                val link = TcpTransport.open(host, port)
                closeLink = link::close
                EventLog.log("стенд ответил")
                link.input to link.output
            } catch (e: Exception) {
                EventLog.log(
                    "стенд не отвечает ($host:$port): ${e.message}. " +
                        "Проверьте, запущен ли эмулятор и сделан ли adb reverse tcp:$port tcp:$port"
                )
                null
            }
        }

    /** Проверки, которые дешевле сделать до запуска потока. */
    private fun usbReady(): Boolean {
        val accessory = AoapTransport.attached(this)
        if (accessory == null) {
            EventLog.log("машина не подключена: воткните провод в порт USB автомобиля")
            update(Stage.WAITING, "нет провода", running = false)
            return false
        }
        if (!AoapTransport.hasPermission(this, accessory)) {
            EventLog.log("нет разрешения на доступ к машине — подтвердите запрос Android")
            AoapTransport.requestPermission(this, accessory)
            return false
        }
        EventLog.log("машина на проводе: ${AoapTransport.describe(accessory)}")
        return true
    }

    private fun disconnect() {
        keepWaiting = false
        listener?.close()
        listener = null
        session?.stop()
        session = null
        closeLink?.invoke()
        closeLink = null
        worker?.let { if (it !== Thread.currentThread()) it.join(700) }
        worker = null
        projection?.stop()
        projection = null
        update(Stage.CLOSED, "", running = false)
    }

    private fun update(stage: Stage, detail: String, running: Boolean = true) {
        state.value = LinkState(stage, detail, running && stage != Stage.CLOSED)
    }

    private fun goForeground(withCapture: Boolean) {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification: Notification = Notification.Builder(this, CarLinkApp.CHANNEL_ID)
            .setContentTitle("CarLink")
            .setContentText(if (Settings.transport(this) == Transport.WIFI) "Жду подключение автомобиля" else "Соединение с автомобилем")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(open)
            .setOngoing(true)
            .build()

        var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        if (withCapture) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        startForeground(NOTIFICATION_ID, notification, type)
    }

    companion object {
        const val ACTION_START = "kz.carlink.START"
        const val ACTION_STOP = "kz.carlink.STOP"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"

        private const val NOTIFICATION_ID = 1

        private val mainHandler = Handler(Looper.getMainLooper())

        private val _state = MutableStateFlow(LinkState())
        val state: MutableStateFlow<LinkState> get() = _state
        val status: StateFlow<LinkState> get() = _state

        fun start(context: Context, resultCode: Int, resultData: Intent?) {
            val intent = Intent(context, CarLinkService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_RESULT_DATA, resultData)
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.startService(Intent(context, CarLinkService::class.java).apply { action = ACTION_STOP })
        }
    }
}
