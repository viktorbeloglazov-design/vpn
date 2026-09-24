package kz.qpvpn.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

/**
 * Проверка, что через туннель проходят большие порции данных.
 *
 * Слишком большой пакет — самая частая причина жалоб вида «сообщения
 * отправляются, а видео крутится и не скачивается». Мелкие пакеты
 * пролезают, крупные сеть не пропускает целиком, и каждая порция уходит
 * заново: связь вроде есть, а толку нет.
 *
 * Отличить это от просто медленной сети помогает порядок величин: даже на
 * плохом мобильном интернете сотня килобайт приходит за несколько секунд,
 * а при неподходящем размере пакета не приходит вовсе.
 */
object BulkCheck {

    /** Столько байт достаточно, чтобы задеть проблему с размером пакета. */
    private const val NEEDED = 128 * 1024

    private const val TIMEOUT_MILLIS = 9_000

    /** Источники на случай, если один недоступен. */
    private val sources = listOf(
        "https://speed.cloudflare.com/__down?bytes=1000000",
        "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png",
        "https://raw.githubusercontent.com/viktorbeloglazov-design/vpn/main/README.md",
        // Тот же путь, которым идут фото и видео в мессенджере: если
        // крупные порции не проходят именно там, остальное не показательно.
        "https://static.whatsapp.net/rsrc.php/yb/r/Rq2c0nGrPYC.js",
    )

    /** Чем кончилась проверка. */
    enum class Verdict {
        /** Большие порции проходят — размер пакета подходит. */
        PASSES,

        /** Соединение есть, данные не идут — размер пакета великоват. */
        STALLS,

        /**
         * Проверить не вышло: ни один источник не отозвался.
         *
         * Раньше этот случай считался успехом — «раз не проверили, значит
         * всё хорошо». Из-за этого телефон оставался с размером пакета из
         * ключа, а человек потом не мог скачать ни фото, ни видео. Теперь
         * неизвестность — это неизвестность, и размер берётся заведомо
         * проходимый.
         */
        UNKNOWN,
    }

    suspend fun check(): Verdict = withContext(Dispatchers.IO) {
        for (source in sources) {
            when (download(source)) {
                Result.OK -> return@withContext Verdict.PASSES
                Result.STALLED -> return@withContext Verdict.STALLS
                Result.UNREACHABLE -> Unit  // источник недоступен — пробуем следующий
            }
        }
        Verdict.UNKNOWN
    }

    private enum class Result { OK, STALLED, UNREACHABLE }

    private fun download(url: String): Result {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 5_000
                readTimeout = TIMEOUT_MILLIS
                useCaches = false
            }
            if (connection.responseCode !in 200..299) return Result.UNREACHABLE

            val deadline = System.currentTimeMillis() + TIMEOUT_MILLIS
            var total = 0
            val buffer = ByteArray(32 * 1024)

            connection.inputStream.use { stream ->
                while (total < NEEDED && System.currentTimeMillis() < deadline) {
                    val read = stream.read(buffer)
                    if (read <= 0) break
                    total += read
                }
            }

            // Файл кончился раньше — значит, он просто небольшой и дошёл целиком.
            if (total >= NEEDED || total >= connection.contentLength) Result.OK else Result.STALLED
        } catch (error: java.net.SocketTimeoutException) {
            // Соединение установилось, а данные не идут — это как раз оно.
            Result.STALLED
        } catch (error: Exception) {
            Result.UNREACHABLE
        } finally {
            connection?.disconnect()
        }
    }
}
