package ru.carpanel

import android.app.Application
import android.content.Context
import ru.carpanel.apps.AppCatalog
import ru.carpanel.data.Locales
import ru.carpanel.data.Store
import ru.carpanel.media.MediaHub

/** Общие на всю программу хранилище, список программ и пульт проигрывателя. */
class PanelApp : Application() {

    val store: Store by lazy { Store(this) }
    val catalog: AppCatalog by lazy { AppCatalog(this) }
    val media: MediaHub by lazy { MediaHub(this) }

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(Locales.wrap(base))
    }

    companion object {
        fun of(context: Context): PanelApp = context.applicationContext as PanelApp
    }
}
