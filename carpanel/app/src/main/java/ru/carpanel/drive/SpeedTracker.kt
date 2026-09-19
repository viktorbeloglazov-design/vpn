package ru.carpanel.drive

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import androidx.core.content.ContextCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Что показывать на плитках «Спидометр» и «Поездка». */
data class SpeedSnapshot(
    val speedMs: Float = 0f,
    /** Когда пришло последнее показание: по нему видно, что сигнал пропал. */
    val updatedAtMs: Long = 0L,
    val allowed: Boolean = false,
    val gpsEnabled: Boolean = true,
    val trip: TripState = TripState(),
) {
    val hasFix: Boolean get() = updatedAtMs > 0L

    /** Показание считается свежим 8 секунд — дальше это уже не скорость. */
    fun isFresh(nowMs: Long): Boolean = hasFix && nowMs - updatedAtMs < 8_000L
}

/**
 * Скорость и путь от встроенного GPS.
 *
 * Сервисы Google не нужны: в машине их может не быть, поэтому берём
 * показания напрямую у системной службы определения места.
 */
class SpeedTracker(private val context: Context) : LocationListener {

    private val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager

    private val _state = MutableStateFlow(SpeedSnapshot())
    val state: StateFlow<SpeedSnapshot> = _state.asStateFlow()

    private var listening = false

    /** Дано ли разрешение на определение места. */
    fun allowed(): Boolean {
        val fine = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION)
        return fine == PackageManager.PERMISSION_GRANTED || coarse == PackageManager.PERMISSION_GRANTED
    }

    private fun gpsEnabled(): Boolean =
        runCatching { manager?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true }.getOrDefault(false)

    @SuppressLint("MissingPermission")
    fun start() {
        _state.value = _state.value.copy(allowed = allowed(), gpsEnabled = gpsEnabled())
        val lm = manager ?: return
        if (!allowed() || listening) return

        val gps = runCatching {
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1_000L, 0f, this)
        }.isSuccess
        val network = runCatching {
            lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 2_000L, 0f, this)
        }.isSuccess
        listening = gps || network
    }

    fun stop() {
        if (!listening) return
        runCatching { manager?.removeUpdates(this) }
        listening = false
    }

    /** Обнулить счётчик поездки. */
    fun resetTrip() {
        _state.value = _state.value.copy(trip = TripState())
    }

    override fun onLocationChanged(location: Location) {
        val fix = Fix(
            timeMs = if (location.time > 0L) location.time else System.currentTimeMillis(),
            lat = location.latitude,
            lon = location.longitude,
            speedMs = if (location.hasSpeed()) location.speed else null,
            accuracyM = if (location.hasAccuracy()) location.accuracy else 0f,
        )

        val current = _state.value
        val speed = TripMath.speed(current.trip.lastFix, fix)
        val trip = TripMath.update(current.trip, fix)
        if (trip === current.trip) return

        _state.value = current.copy(
            speedMs = speed,
            updatedAtMs = System.currentTimeMillis(),
            allowed = true,
            gpsEnabled = gpsEnabled(),
            trip = trip,
        )
    }

    override fun onProviderEnabled(provider: String) {
        _state.value = _state.value.copy(gpsEnabled = gpsEnabled())
    }

    override fun onProviderDisabled(provider: String) {
        _state.value = _state.value.copy(gpsEnabled = gpsEnabled())
    }

    // На Android 10 и старше этот метод обязателен: без него система
    // уронит программу, как только приёмник сменит состояние.
    @Deprecated("Оставлен ради старых версий Android")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
}
