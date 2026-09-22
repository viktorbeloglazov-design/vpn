package kz.qpvpn.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
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

    /** Сколько раз пробуем продолжить оборвавшуюся закачку. */
    private const val ATTEMPTS = 8

    /**
     * Скачивает сборку. Возвращает файл или null.
     *
     * Качает по частям и продолжает с места обрыва. Сборки раздаются
     * с адреса, который в России режется: на большом файле связь рвётся
     * посередине, и закачка с нуля не доходит никогда. Поэтому при обрыве
     * не начинаем заново, а дописываем недостающее.
     *
     * Кладём в свой каталог кэша: оттуда его отдаёт системному установщику
     * наш же файловый поставщик, и лишних разрешений не нужно.
     */
    suspend fun download(
        directory: File,
        url: String = APK_URL,
        onProgress: (Int) -> Unit = {},
    ): File? =
        withContext(Dispatchers.IO) {
            val target = File(directory, "QPVPN-update.apk")
            target.delete()

            var total = 0L
            // Метка версии файла на сервере. С ней сервер сам решит, можно ли
            // дописывать: если сборку успели заменить, он отдаст её целиком,
            // а не приклеит кусок от другой.
            var tag: String? = null

            repeat(ATTEMPTS) { attempt ->
                val have = if (target.exists()) target.length() else 0L
                if (total > 0 && have >= total) return@withContext verify(target, total)

                var connection: HttpURLConnection? = null
                try {
                    connection = (URL(url).openConnection() as HttpURLConnection).apply {
                        connectTimeout = 20_000
                        readTimeout = 30_000
                        instanceFollowRedirects = true
                        useCaches = false
                        if (have > 0) {
                            setRequestProperty("Range", "bytes=$have-")
                            tag?.let { setRequestProperty("If-Range", it) }
                        }
                    }

                    val code = connection.responseCode
                    if (code !in 200..299) return@repeat

                    // 206 — сервер дописывает с нужного места. 200 — отдаёт
                    // файл целиком, значит написанное раньше надо выбросить.
                    val appending = code == 206 && have > 0
                    if (!appending && have > 0) target.delete()

                    if (tag == null) {
                        tag = connection.getHeaderField("ETag")
                            ?: connection.getHeaderField("Last-Modified")
                    }

                    val startAt = if (appending) have else 0L
                    if (total == 0L || !appending) {
                        total = connection.contentLengthLong.takeIf { it > 0 }?.plus(startAt) ?: 0L
                    }

                    var done = startAt
                    FileOutputStream(target, appending).use { output ->
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

                    // Размер известен — дошли до конца. Не известен (сервер
                    // отдаёт потоком) — значит поток кончился сам, и это тоже
                    // конец файла.
                    if (total == 0L || done >= total) return@withContext verify(target, total)
                } catch (error: Exception) {
                    // Обрыв посередине — это ожидаемое поведение канала,
                    // а не повод всё стереть: скачанное пригодится.
                } finally {
                    connection?.disconnect()
                }

                // Пауза перед следующей попыткой: сразу ломиться бесполезно.
                Thread.sleep(minOf(1_000L * (attempt + 1), 5_000L))
            }

            target.delete()
            null
        }

    /**
     * Проверяет, что скачан именно APK, а не страница с ошибкой.
     *
     * Оборванная или подменённая закачка даёт файл, на котором установщик
     * покажет невнятное «пакет повреждён». Лучше поймать это сразу.
     */
    private fun verify(file: File, expected: Long): File? {
        val head = ByteArray(2)
        val sizeMatches = expected == 0L || file.length() == expected
        val readOk = try {
            file.inputStream().use { it.read(head) } == 2
        } catch (error: Exception) {
            false
        }
        // APK — это ZIP, а ZIP всегда начинается с этих двух букв. Если вместо
        // сборки пришла страница с ошибкой, здесь будет что угодно другое.
        val looksLikeApk = head[0] == 'P'.code.toByte() && head[1] == 'K'.code.toByte()

        if (!sizeMatches || !readOk || !looksLikeApk) {
            file.delete()
            return null
        }
        return file
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
