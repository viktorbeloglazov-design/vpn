package kz.qpvpn.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Проверка и скачивание обновления.
 *
 * Приложение ставится файлом, мимо магазина, поэтому напомнить о новой
 * версии некому — приходится делать это самим. Рядом со сборкой лежит файл
 * с номером версии строкой: его и читаем, он весит десяток байт.
 *
 * Ссылки постоянные: имя файла без номера, выпуск с меткой latest. Они не
 * меняются от версии к версии, поэтому ничего настраивать не нужно.
 */
object UpdateCheck {

    private const val BASE =
        "https://github.com/viktorbeloglazov-design/vpn/releases/download/latest"

    private const val VERSION_URL = "$BASE/android-version.txt"
    private const val APK_URL = "$BASE/QPVPN-android.apk"

    /** Раз в сутки — чаще незачем, реже можно пропустить важное. */
    const val CHECK_INTERVAL_MILLIS = 24 * 60 * 60 * 1000L

    /** Свежая версия на сервере, либо null — узнать не вышло. */
    suspend fun latestVersion(): String? = withContext(Dispatchers.IO) {
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(VERSION_URL).openConnection() as HttpURLConnection).apply {
                connectTimeout = 10_000
                readTimeout = 10_000
                useCaches = false
            }
            if (connection.responseCode !in 200..299) return@withContext null
            val text = connection.inputStream.bufferedReader().use { it.readText() }.trim()
            text.takeIf { it.isNotEmpty() && it.first().isDigit() }
        } catch (error: Exception) {
            null
        } finally {
            connection?.disconnect()
        }
    }

    /**
     * Скачивает сборку. Возвращает файл или null.
     *
     * Кладём в свой каталог кэша: оттуда его отдаёт системному установщику
     * наш же файловый поставщик, и лишних разрешений не нужно.
     */
    suspend fun download(directory: File, onProgress: (Int) -> Unit = {}): File? =
        withContext(Dispatchers.IO) {
            var connection: HttpURLConnection? = null
            val target = File(directory, "QPVPN-update.apk")
            try {
                connection = (URL(APK_URL).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 15_000
                    readTimeout = 30_000
                    instanceFollowRedirects = true
                    useCaches = false
                }
                if (connection.responseCode !in 200..299) return@withContext null

                val total = connection.contentLengthLong
                var done = 0L
                target.outputStream().use { output ->
                    connection.inputStream.use { input ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read <= 0) break
                            output.write(buffer, 0, read)
                            done += read
                            if (total > 0) onProgress((done * 100 / total).toInt())
                        }
                    }
                }
                // Оборванная закачка даёт битый файл: установщик покажет
                // невнятную ошибку, поэтому лучше сразу считать её неудачей.
                if (total > 0 && done < total) {
                    target.delete()
                    null
                } else {
                    target
                }
            } catch (error: Exception) {
                target.delete()
                null
            } finally {
                connection?.disconnect()
            }
        }

    /**
     * Свежее ли «1.2.10», чем «1.2.9».
     *
     * Сравниваем числами по частям: по буквам «10» оказалось бы меньше «9».
     */
    fun isNewer(candidate: String, current: String): Boolean {
        val left = parts(candidate)
        val right = parts(current)
        for (index in 0 until maxOf(left.size, right.size)) {
            val a = left.getOrElse(index) { 0 }
            val b = right.getOrElse(index) { 0 }
            if (a != b) return a > b
        }
        return false
    }

    private fun parts(version: String): List<Int> =
        version.trim().split('.', '-', '+')
            .mapNotNull { piece -> piece.takeWhile { it.isDigit() }.toIntOrNull() }
}
