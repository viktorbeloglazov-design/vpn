package kz.qpvpn.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import kz.qpvpn.MainActivity
import kz.qpvpn.QpVpnApp
import kz.qpvpn.R
import kz.qpvpn.ui.Format

/**
 * Значок в строке состояния, пока туннель поднят.
 *
 * Системный ключик Android рисует сам, но многие оболочки (Xiaomi, Honor,
 * Samsung) его прячут — человек включает VPN и не видит наверху ничего.
 * Поэтому приложение держит собственное уведомление: его значок оболочки
 * не прячут, и рядом сразу видно сервер, трафик и кнопку «Отключить».
 */
object VpnNotification {

    private const val CHANNEL_ID = "qpvpn.status"
    private const val ID = 1
    const val ACTION_DISCONNECT = "kz.qpvpn.action.DISCONNECT"

    /** Показывает или обновляет уведомление о работающем туннеле. */
    fun show(
        context: Context,
        connected: Boolean,
        server: String,
        rxBytes: Long,
        txBytes: Long,
    ) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        ensureChannel(manager)

        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stop = PendingIntent.getBroadcast(
            context,
            1,
            Intent(context, DisconnectReceiver::class.java).setAction(ACTION_DISCONNECT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val text = when {
            !connected -> "Устанавливаю связь…"
            server.isNotEmpty() -> "$server · ${Format.bytes(rxBytes)} ↓ ${Format.bytes(txBytes)} ↑"
            else -> "${Format.bytes(rxBytes)} ↓ ${Format.bytes(txBytes)} ↑"
        }

        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_vpn)
            .setContentTitle(if (connected) "QP VPN подключён" else "QP VPN подключается")
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Отключить", stop).build())
            .build()

        try {
            manager.notify(ID, notification)
        } catch (error: SecurityException) {
            // Уведомления запрещены — значка не будет, но туннель работает.
            // На экране для этого случая есть отдельная подсказка.
        }
    }

    fun hide(context: Context) {
        context.getSystemService(NotificationManager::class.java)?.cancel(ID)
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Состояние VPN", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Значок в строке состояния, пока туннель поднят"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
        )
    }
}

/** Кнопка «Отключить» в уведомлении. */
class DisconnectReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != VpnNotification.ACTION_DISCONNECT) return
        val app = context.applicationContext as? QpVpnApp ?: return
        app.tunnel.requestDisconnect()
    }
}
