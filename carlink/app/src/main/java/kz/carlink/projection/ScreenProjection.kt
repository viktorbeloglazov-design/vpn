package kz.carlink.projection

import android.content.Context
import android.graphics.PointF
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.DisplayMetrics
import android.view.Display
import android.view.MotionEvent
import android.view.WindowManager
import kz.carlink.aa.FrameSink
import kz.carlink.aa.Projection
import kz.carlink.aa.TouchEvent
import kz.carlink.aa.VideoConfig

/** Что показывать машине. */
enum class ProjectionMode {
    /** Свой экран для машины: часы, управление музыкой. Ничего лишнего. */
    CAR_UI,

    /** Зеркало экрана телефона: видно карты и любые программы. */
    MIRROR,
}

/**
 * Готовит картинку для машины и принимает от неё касания.
 *
 * Оба режима работают через виртуальный экран: в режиме зеркала на него
 * системой копируется настоящий экран телефона, в режиме своего интерфейса на
 * нём живёт отдельное окно (см. [CarPresentation]).
 *
 * Касания возвращаются в координатах экрана машины. Для своего интерфейса их
 * можно отдать окну напрямую, а вот в зеркальном режиме нажать за телефон может
 * только служба специальных возможностей — [TouchInjector].
 */
class ScreenProjection(
    private val context: Context,
    private val mode: ProjectionMode,
    private val mediaProjection: () -> MediaProjection?,
    private val log: (String) -> Unit,
) : Projection {

    private val main = Handler(Looper.getMainLooper())

    private var encoder: VideoEncoder? = null
    private var display: VirtualDisplay? = null
    private var presentation: CarPresentation? = null

    private var downTime = 0L
    private val dragPath = ArrayList<PointF>()

    override fun start(config: VideoConfig, sink: FrameSink) {
        stop()
        val encoder = VideoEncoder(config.width, config.height, config.fps, log)
        encoder.start(sink)
        this.encoder = encoder
        val surface = encoder.surface ?: error("кодировщик не отдал поверхность")

        when (mode) {
            ProjectionMode.MIRROR -> {
                val projection = mediaProjection()
                    ?: error("нет разрешения на захват экрана — выдайте его в приложении")
                display = projection.createVirtualDisplay(
                    "carlink-mirror",
                    config.width,
                    config.height,
                    config.dpi,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    surface,
                    null,
                    null,
                )
                log("зеркалю экран телефона на ${config.width}×${config.height}")
            }

            ProjectionMode.CAR_UI -> {
                val manager = context.getSystemService(DisplayManager::class.java)
                display = manager.createVirtualDisplay(
                    "carlink-ui",
                    config.width,
                    config.height,
                    config.dpi,
                    surface,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_PRESENTATION or
                        DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY,
                )
                val target = display?.display
                if (target != null) main.post { showPresentation(target) }
            }
        }
    }

    private fun showPresentation(target: Display) {
        try {
            presentation = CarPresentation(context, target).also { it.show() }
            log("свой экран для машины открыт")
        } catch (e: Exception) {
            // Окно на виртуальном экране система разрешает не всегда: из службы
            // в фоне его могут не пустить. Тогда остаётся режим зеркала.
            log("не смог открыть свой экран (${e.javaClass.simpleName}). Переключитесь на режим зеркала.")
        }
    }

    override fun stop() {
        main.post {
            runCatching { presentation?.dismiss() }
            presentation = null
        }
        runCatching { display?.release() }
        display = null
        encoder?.stop()
        encoder = null
    }

    override fun touch(event: TouchEvent, config: VideoConfig) {
        val pointer = event.pointers.firstOrNull() ?: return
        when (mode) {
            ProjectionMode.CAR_UI -> dispatchToPresentation(event, pointer.x.toFloat(), pointer.y.toFloat())
            ProjectionMode.MIRROR -> dispatchToPhone(event, pointer.x.toFloat(), pointer.y.toFloat(), config)
        }
    }

    private fun dispatchToPresentation(event: TouchEvent, x: Float, y: Float) {
        val action = when (event.action) {
            TouchEvent.PRESS -> MotionEvent.ACTION_DOWN
            TouchEvent.RELEASE -> MotionEvent.ACTION_UP
            TouchEvent.DRAG -> MotionEvent.ACTION_MOVE
            else -> return
        }
        if (action == MotionEvent.ACTION_DOWN) downTime = SystemClock.uptimeMillis()
        val now = SystemClock.uptimeMillis()
        main.post {
            val motion = MotionEvent.obtain(downTime, now, action, x, y, 0)
            runCatching { presentation?.window?.decorView?.dispatchTouchEvent(motion) }
            motion.recycle()
        }
    }

    /**
     * Пересчитывает точку с экрана машины в точку на экране телефона.
     * Зеркало вписывает экран целиком, поэтому по краям остаются поля — их и
     * вычитаем, иначе нажатия уезжают.
     */
    private fun dispatchToPhone(event: TouchEvent, x: Float, y: Float, config: VideoConfig) {
        val injector = TouchInjector.instance
        if (injector == null) {
            log("нажатия не проходят: включите «CarLink» в специальных возможностях")
            return
        }
        val phone = phoneScreenSize() ?: return
        val scale = minOf(config.width.toFloat() / phone.x, config.height.toFloat() / phone.y)
        val offsetX = (config.width - phone.x * scale) / 2f
        val offsetY = (config.height - phone.y * scale) / 2f
        val point = PointF((x - offsetX) / scale, (y - offsetY) / scale)
        if (point.x < 0 || point.y < 0 || point.x > phone.x || point.y > phone.y) return

        when (event.action) {
            TouchEvent.PRESS -> {
                dragPath.clear()
                dragPath += point
            }
            TouchEvent.DRAG -> if (dragPath.isNotEmpty()) dragPath += point
            TouchEvent.RELEASE -> {
                dragPath += point
                injector.playPath(dragPath.toList())
                dragPath.clear()
            }
        }
    }

    private fun phoneScreenSize(): PointF? {
        val windowManager = context.getSystemService(WindowManager::class.java) ?: return null
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(metrics)
        if (metrics.widthPixels == 0) return null
        return PointF(metrics.widthPixels.toFloat(), metrics.heightPixels.toFloat())
    }
}
