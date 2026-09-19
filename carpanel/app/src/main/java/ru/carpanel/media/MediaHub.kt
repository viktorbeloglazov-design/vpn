package ru.carpanel.media

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.provider.Settings

/** Что играет прямо сейчас. */
data class MediaSnapshot(
    val available: Boolean = false,
    val playing: Boolean = false,
    val title: String = "",
    val subtitle: String = "",
    val packageName: String? = null,
)

/**
 * Управление чужим проигрывателем.
 *
 * Работает через тот же механизм, что и кнопки на руле: система отдаёт
 * список сеансов воспроизведения, а мы дёргаем у них «пауза», «дальше»
 * и «назад». Требуется разрешение «доступ к уведомлениям».
 */
class MediaHub(private val context: Context) {

    private val component = ComponentName(context, PanelNotificationListener::class.java)

    private val manager: MediaSessionManager?
        get() = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager

    /** Выдано ли разрешение «доступ к уведомлениям». */
    fun hasAccess(): Boolean {
        val enabled = runCatching {
            Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
        }.getOrNull() ?: return false
        return enabled.split(':').any { it.contains(context.packageName) }
    }

    /** Экран системных настроек, где это разрешение выдают. */
    fun accessSettingsIntent(): Intent =
        Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /**
     * Проигрыватель, которым управляем.
     *
     * Сначала тот, что указан на плитке (например, Яндекс Музыка), затем —
     * играющий прямо сейчас, и только потом первый попавшийся.
     */
    fun controller(preferred: String? = null): MediaController? {
        val sessions = runCatching { manager?.getActiveSessions(component) }
            .getOrNull()
            .orEmpty()
        if (sessions.isEmpty()) return null
        return sessions.firstOrNull { it.packageName == preferred && isPlaying(it) }
            ?: sessions.firstOrNull { it.packageName == preferred }
            ?: sessions.firstOrNull { isPlaying(it) }
            ?: sessions.firstOrNull()
    }

    fun snapshot(preferred: String? = null): MediaSnapshot {
        if (!hasAccess()) return MediaSnapshot()
        val controller = controller(preferred) ?: return MediaSnapshot(available = true)
        val metadata = runCatching { controller.metadata }.getOrNull()
        return MediaSnapshot(
            available = true,
            playing = isPlaying(controller),
            title = metadata?.text(MediaMetadata.METADATA_KEY_TITLE).orEmpty(),
            subtitle = metadata?.text(MediaMetadata.METADATA_KEY_ARTIST)
                ?: metadata?.text(MediaMetadata.METADATA_KEY_ALBUM).orEmpty(),
            packageName = controller.packageName,
        )
    }

    fun playPause(preferred: String? = null) {
        val controller = controller(preferred) ?: return
        runCatching {
            if (isPlaying(controller)) controller.transportControls.pause()
            else controller.transportControls.play()
        }
    }

    fun next(preferred: String? = null) {
        runCatching { controller(preferred)?.transportControls?.skipToNext() }
    }

    fun previous(preferred: String? = null) {
        runCatching { controller(preferred)?.transportControls?.skipToPrevious() }
    }

    private fun isPlaying(controller: MediaController): Boolean =
        runCatching { controller.playbackState?.state == PlaybackState.STATE_PLAYING }.getOrDefault(false)

    private fun MediaMetadata.text(key: String): String? =
        runCatching { getString(key) }.getOrNull()?.takeIf { it.isNotBlank() }
}
