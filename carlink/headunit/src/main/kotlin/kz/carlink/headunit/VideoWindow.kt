package kz.carlink.headunit

import kz.carlink.aa.Pointer
import kz.carlink.aa.TouchEvent
import java.awt.BorderLayout
import java.awt.Color
import java.awt.Dimension
import java.awt.Graphics
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.image.BufferedImage
import javax.swing.BorderFactory
import javax.swing.JFrame
import javax.swing.JLabel
import javax.swing.JPanel
import javax.swing.SwingUtilities
import javax.swing.WindowConstants

/**
 * Окно стенда: слева то, что прислал телефон, снизу — состояние.
 *
 * Мышь работает как сенсорный экран машины: нажатие, протяжка и отпускание
 * уходят телефону теми же сообщениями, что шлёт настоящее головное устройство.
 * Координаты пересчитываются из окна в разрешение «экрана машины», поэтому
 * размер окна можно менять как угодно.
 */
class VideoWindow(
    private val carWidth: Int,
    private val carHeight: Int,
    private val onTouch: (TouchEvent) -> Unit,
) {
    private val frame = JFrame("CarLink — стенд головного устройства")
    private val status = JLabel("жду телефон")

    @Volatile
    private var image: BufferedImage? = null

    @Volatile
    private var hint = "картинки пока нет"

    private val canvas = object : JPanel() {
        override fun paintComponent(graphics: Graphics) {
            super.paintComponent(graphics)
            val current = image
            if (current == null) {
                graphics.color = Color(0x8F, 0xA3, 0xB8)
                graphics.drawString(hint, 24, 32)
                return
            }
            val box = fitBox()
            graphics.drawImage(current, box[0], box[1], box[2], box[3], null)
        }
    }

    fun open() = SwingUtilities.invokeLater {
        canvas.background = Color(0x0B, 0x0F, 0x14)
        canvas.preferredSize = Dimension(carWidth, carHeight)
        canvas.addMouseListener(object : MouseAdapter() {
            override fun mousePressed(e: MouseEvent) = touch(TouchEvent.PRESS, e)
            override fun mouseReleased(e: MouseEvent) = touch(TouchEvent.RELEASE, e)
        })
        canvas.addMouseMotionListener(object : MouseAdapter() {
            override fun mouseDragged(e: MouseEvent) = touch(TouchEvent.DRAG, e)
        })

        status.border = BorderFactory.createEmptyBorder(6, 10, 6, 10)

        frame.layout = BorderLayout()
        frame.add(canvas, BorderLayout.CENTER)
        frame.add(status, BorderLayout.SOUTH)
        frame.defaultCloseOperation = WindowConstants.EXIT_ON_CLOSE
        frame.pack()
        frame.setLocationRelativeTo(null)
        frame.isVisible = true
    }

    fun show(next: BufferedImage) {
        image = next
        canvas.repaint()
    }

    fun hint(text: String) {
        hint = text
        canvas.repaint()
    }

    fun status(text: String) = SwingUtilities.invokeLater { status.text = text }

    private fun touch(action: Int, event: MouseEvent) {
        val box = fitBox()
        if (box[2] == 0 || box[3] == 0) return
        val x = (event.x - box[0]) * carWidth / box[2]
        val y = (event.y - box[1]) * carHeight / box[3]
        if (x < 0 || y < 0 || x >= carWidth || y >= carHeight) return
        onTouch(TouchEvent(action, 0, listOf(Pointer(x, y, 0))))
    }

    /** Куда вписывается «экран машины» в текущем размере окна: x, y, ширина, высота. */
    private fun fitBox(): IntArray {
        val width = canvas.width
        val height = canvas.height
        if (width == 0 || height == 0) return intArrayOf(0, 0, 0, 0)
        val scale = minOf(width.toDouble() / carWidth, height.toDouble() / carHeight)
        val drawWidth = (carWidth * scale).toInt()
        val drawHeight = (carHeight * scale).toInt()
        return intArrayOf((width - drawWidth) / 2, (height - drawHeight) / 2, drawWidth, drawHeight)
    }
}
