package kz.carlink

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager

class CarLinkApp : Application() {

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.channel_name),
                NotificationManager.IMPORTANCE_LOW,
            )
        )
    }

    companion object {
        const val CHANNEL_ID = "carlink-link"
    }
}
