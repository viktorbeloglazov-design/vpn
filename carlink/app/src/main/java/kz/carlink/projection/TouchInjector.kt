package kz.carlink.projection

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.PointF
import android.view.accessibility.AccessibilityEvent

/**
 * Нажимает за пользователя в режиме зеркала.
 *
 * Без прав системного приложения передать касание в чужую программу можно
 * только так — службой специальных возможностей. Расплата за это — задержка:
 * жест уходит целиком в момент, когда палец оторвали от экрана машины, поэтому
 * прокрутка выглядит рывком, а не плавным движением.
 */
class TouchInjector : AccessibilityService() {

    override fun onServiceConnected() {
        instance = this
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    /** Проигрывает записанный путь: короткий — нажатием, длинный — проводкой. */
    fun playPath(points: List<PointF>) {
        if (points.isEmpty()) return
        val path = Path()
        path.moveTo(points.first().x, points.first().y)
        var length = 0f
        for (i in 1 until points.size) {
            val previous = points[i - 1]
            val current = points[i]
            length += kotlin.math.hypot(current.x - previous.x, current.y - previous.y)
            path.lineTo(current.x, current.y)
        }
        val duration = if (length < TAP_SLOP) TAP_DURATION else (length / SPEED_PX_PER_MS).toLong().coerceIn(60L, 700L)
        val stroke = GestureDescription.StrokeDescription(path, 0, duration)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, null, null)
    }

    companion object {
        @Volatile
        var instance: TouchInjector? = null
            private set

        private const val TAP_SLOP = 12f
        private const val TAP_DURATION = 50L
        private const val SPEED_PX_PER_MS = 2.5f
    }
}
