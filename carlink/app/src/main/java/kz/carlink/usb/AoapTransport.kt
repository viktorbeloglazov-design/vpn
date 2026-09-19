package kz.carlink.usb

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbAccessory
import android.hardware.usb.UsbManager
import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException

/**
 * Провод до машины.
 *
 * По USB головное устройство — хозяин шины, телефон — «аксессуар» (протокол
 * AOAP). Машина сама переводит телефон в этот режим и представляется строками
 * производителя и модели; Android по ним находит приложение и отдаёт ему пару
 * потоков — на чтение и на запись. Больше ничего настраивать не нужно.
 */
class AoapTransport private constructor(
    val accessory: UsbAccessory,
    private val descriptor: ParcelFileDescriptor,
) {
    val input = FileInputStream(descriptor.fileDescriptor)
    val output = FileOutputStream(descriptor.fileDescriptor)

    fun close() {
        runCatching { input.close() }
        runCatching { output.close() }
        runCatching { descriptor.close() }
    }

    companion object {
        const val PERMISSION_ACTION = "kz.carlink.USB_PERMISSION"

        fun describe(accessory: UsbAccessory): String =
            listOfNotNull(
                accessory.manufacturer,
                accessory.model,
                accessory.description,
                accessory.version?.let { "версия $it" },
            ).joinToString(" · ")

        fun attached(context: Context): UsbAccessory? {
            val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
            return manager.accessoryList?.firstOrNull()
        }

        fun hasPermission(context: Context, accessory: UsbAccessory): Boolean {
            val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
            return manager.hasPermission(accessory)
        }

        fun requestPermission(context: Context, accessory: UsbAccessory) {
            val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
            val intent = PendingIntent.getBroadcast(
                context,
                0,
                Intent(PERMISSION_ACTION).setPackage(context.packageName),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            manager.requestPermission(accessory, intent)
        }

        fun open(context: Context, accessory: UsbAccessory): AoapTransport {
            val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
            val descriptor = manager.openAccessory(accessory)
                ?: throw IOException("не удалось открыть соединение с машиной")
            return AoapTransport(accessory, descriptor)
        }
    }
}
