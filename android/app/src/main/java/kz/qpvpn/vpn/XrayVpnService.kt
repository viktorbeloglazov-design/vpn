package kz.qpvpn.vpn

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.ParcelFileDescriptor
import kotlinx.coroutines.CompletableDeferred
import xraylib.Protector
import xraylib.Xraylib

/**
 * Служба VPN для ключей X-Ray.
 *
 * Прежние ключи поднимала библиотека AmneziaWG со своей службой. Для
 * X-Ray служба своя: она заводит туннель системы, а пакеты из него
 * отдаёт библиотеке xraylib — там tun2socks передаёт их в xray, а xray
 * на сервер. Какие адреса идут в туннель и какие программы его не видят,
 * решает прежняя маршрутизация: служба только исполняет список.
 */
class XrayVpnService : VpnService() {

    /** Что поднять: собирается в TunnelController по тем же правилам, что и раньше. */
    data class Request(
        val configJson: String,
        val routes: List<String>,
        val ipv6: Boolean,
        val dns: List<String>,
        val disallowedApps: List<String>,
        val mtu: Int,
    )

    companion object {
        private const val ACTION_START = "kz.qpvpn.xray.START"
        private const val ACTION_STOP = "kz.qpvpn.xray.STOP"

        /** Адрес туннеля — из частного диапазона, с настоящими не пересечётся. */
        private const val ADDRESS = "172.19.0.1"
        private const val ADDRESS_V6 = "fdfe:dcba:9876::1"

        @Volatile
        private var pending: Request? = null

        @Volatile
        private var outcome: CompletableDeferred<String?>? = null

        @Volatile
        private var instance: XrayVpnService? = null

        /** Туннель X-Ray поднят. */
        @Volatile
        var running: Boolean = false
            private set

        /**
         * Поднимает туннель. Возвращает null, если поднялся, иначе — что
         * показать человеку.
         */
        suspend fun start(context: Context, request: Request): String? {
            val done = CompletableDeferred<String?>()
            pending = request
            outcome = done
            context.startService(Intent(context, XrayVpnService::class.java).setAction(ACTION_START))
            return kotlinx.coroutines.withTimeoutOrNull(30_000) { done.await() }
                ?: "Туннель X-Ray не поднялся за 30 секунд."
        }

        fun stop(context: Context) {
            instance?.shutdown()
            if (running || instance != null) {
                context.startService(Intent(context, XrayVpnService::class.java).setAction(ACTION_STOP))
            }
        }

        /** Версия xray внутри — для отчёта. */
        fun coreVersion(): String = runCatching { Xraylib.version() }.getOrDefault("")
    }

    /** Туннель поднят и его дескриптор отдан tun2socks. */
    private var tunnelActive = false

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val request = pending
                val done = outcome
                pending = null
                Thread {
                    val error = if (request == null) {
                        "Нет настроек для туннеля X-Ray."
                    } else {
                        runCatching { bringUp(request) }.exceptionOrNull()?.let {
                            shutdown()
                            it.message ?: "Туннель X-Ray не поднялся."
                        }
                    }
                    done?.complete(error)
                }.apply { name = "qpvpn-xray-start" }.start()
            }

            ACTION_STOP -> {
                shutdown()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    @Synchronized
    private fun bringUp(request: Request) {
        shutdown()

        // Соединение xray с сервером должно идти мимо туннеля — иначе
        // оно уйдёт в тот же туннель, который само обслуживает.
        Xraylib.setProtector(object : Protector {
            override fun protect(fd: Long): Boolean = this@XrayVpnService.protect(fd.toInt())
        })
        Xraylib.startXray(request.configJson)

        val builder = Builder()
            .setSession("QP VPN")
            .setMtu(request.mtu)
            .addAddress(ADDRESS, 30)

        for (route in request.routes) {
            val address = route.substringBefore('/')
            val prefix = route.substringAfter('/', "32").toIntOrNull() ?: continue
            runCatching { builder.addRoute(address, prefix) }
        }
        if (request.ipv6) {
            // IPv6 заворачиваем в туннель: иначе в мобильной сети
            // заблокированное откроется по IPv6 мимо VPN.
            builder.addAddress(ADDRESS_V6, 126)
            builder.addRoute("::", 0)
        }
        request.dns.forEach { runCatching { builder.addDnsServer(it) } }

        // Программы, которым VPN мешает жить: МАХ, банки, госуслуги.
        for (name in request.disallowedApps) {
            try {
                builder.addDisallowedApplication(name)
            } catch (error: PackageManager.NameNotFoundException) {
                // Программу удалили — пропускаем.
            }
        }

        val established = builder.establish()
            ?: throw IllegalStateException("Система не дала поднять VPN: разрешение не выдано.")

        // Дескриптор туннеля отдаём tun2socks целиком: он сам закроет его,
        // когда остановится. Раньше им владели оба — и Android, и tun2socks,
        // — и он закрывался дважды. Android такое ловит и роняет приложение:
        // проверка на эмуляторе упала на «fdsan: failed to exchange ownership
        // of file descriptor».
        val fd = established.detachFd()
        try {
            Xraylib.startTun(fd.toLong(), XrayLink.SOCKS_PORT.toLong(), request.mtu.toLong())
        } catch (error: Exception) {
            // tun2socks его не взял — закрываем сами, иначе туннель повиснет.
            runCatching { ParcelFileDescriptor.adoptFd(fd).close() }
            throw error
        }
        tunnelActive = true
        running = true
    }

    @Synchronized
    fun shutdown() {
        // Дескриптор закрывает сам tun2socks — здесь его не трогаем.
        if (tunnelActive) runCatching { Xraylib.stopTun() }
        tunnelActive = false
        runCatching { Xraylib.stopXray() }
        running = false
    }

    override fun onRevoke() {
        // Разрешение отозвали или включили другой VPN.
        shutdown()
        stopSelf()
    }

    override fun onDestroy() {
        shutdown()
        if (instance === this) instance = null
        super.onDestroy()
    }
}
