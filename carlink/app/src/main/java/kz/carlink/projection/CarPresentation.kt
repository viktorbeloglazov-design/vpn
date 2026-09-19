package kz.carlink.projection

import android.app.Presentation
import android.content.Context
import android.graphics.Color
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Display
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Свой экран для машины: часы и управление музыкой крупными кнопками.
 *
 * Кнопки шлют те же события, что и кнопки на гарнитуре, поэтому ими
 * управляется та программа, которая сейчас играет, — отдельная интеграция с
 * каждым плеером не нужна.
 *
 * Показать здесь чужую программу (карты, мессенджер) нельзя: на виртуальном
 * экране живёт только содержимое своего приложения. Для карт есть режим
 * зеркала.
 */
class CarPresentation(context: Context, display: Display) : Presentation(context, display) {

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var clock: TextView
    private val clockFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

    private val tick = object : Runnable {
        override fun run() {
            clock.text = clockFormat.format(Date())
            handler.postDelayed(this, 10_000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(buildContent())
    }

    override fun onStart() {
        super.onStart()
        handler.post(tick)
    }

    override fun onStop() {
        handler.removeCallbacks(tick)
        super.onStop()
    }

    private fun buildContent(): View {
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0B0F14"))
            setPadding(48, 32, 48, 32)
        }

        clock = TextView(context).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 64f)
            text = clockFormat.format(Date())
            gravity = Gravity.CENTER
        }
        root.addView(clock)

        root.addView(TextView(context).apply {
            setTextColor(Color.parseColor("#8FA3B8"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            text = "CarLink · музыка телефона"
            gravity = Gravity.CENTER
            setPadding(0, 8, 0, 40)
        })

        val controls = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        controls.addView(mediaButton("◀◀", KeyEvent.KEYCODE_MEDIA_PREVIOUS))
        controls.addView(mediaButton("▶ ⏸", KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
        controls.addView(mediaButton("▶▶", KeyEvent.KEYCODE_MEDIA_NEXT))
        root.addView(controls)

        root.addView(TextView(context).apply {
            setTextColor(Color.parseColor("#5C6B7A"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            text = "Карты и остальные программы — в режиме «зеркало экрана»"
            gravity = Gravity.CENTER
            setPadding(0, 40, 0, 0)
        })

        return root
    }

    private fun mediaButton(label: String, keyCode: Int): Button = Button(context).apply {
        text = label
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
        setTextColor(Color.WHITE)
        setBackgroundColor(Color.parseColor("#1B2733"))
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, 140).apply {
            marginEnd = 24
        }
        minWidth = 260
        setOnClickListener { sendMediaKey(keyCode) }
    }

    private fun sendMediaKey(keyCode: Int) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
    }
}
