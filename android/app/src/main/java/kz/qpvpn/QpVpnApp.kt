package kz.qpvpn

import android.app.Application
import kz.qpvpn.data.Store
import kz.qpvpn.vpn.TunnelController

class QpVpnApp : Application() {

    lateinit var store: Store
        private set

    lateinit var tunnel: TunnelController
        private set

    override fun onCreate() {
        super.onCreate()
        store = Store(this)
        tunnel = TunnelController(this, store)
    }
}
