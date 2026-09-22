package kz.qpvpn

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import kz.qpvpn.net.UpdateCheck
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import java.net.InetSocketAddress
import java.nio.file.Files
import java.util.concurrent.atomic.AtomicInteger

/**
 * Докачка после обрыва.
 *
 * Сборки раздаются с адреса, который в России режется: связь рвётся
 * посередине большого файла. Закачка с нуля в таком канале не доходит
 * никогда, поэтому приложение обязано продолжать с места обрыва.
 *
 * Поднимаем свой сервер, который честно рвёт соединение, и проверяем,
 * что файл всё равно собирается целиком и побайтово совпадает с исходным.
 */
class ResumeDownloadTest {

    /** «PK» в начале — как у настоящего APK, дальше просто узнаваемый мусор. */
    private val content = ByteArray(300_000) { index ->
        when (index) {
            0 -> 'P'.code.toByte()
            1 -> 'K'.code.toByte()
            else -> (index % 251).toByte()
        }
    }

    private lateinit var server: HttpServer
    private val breaks = AtomicInteger(0)

    /** Сколько первых ответов оборвать на середине. */
    private var breakFirst = 0

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/apk") { exchange ->
            val range = exchange.requestHeaders.getFirst("Range")
            val from = range?.removePrefix("bytes=")?.substringBefore('-')?.toIntOrNull() ?: 0
            val rest = content.copyOfRange(from, content.size)

            exchange.sendResponseHeaders(if (from > 0) 206 else 200, rest.size.toLong())
            val body = exchange.responseBody
            if (breaks.get() < breakFirst) {
                // Обещали целое, отдаём половину и обрываем — ровно так
                // ведёт себя канал, из-за которого всё это и понадобилось.
                breaks.incrementAndGet()
                body.write(rest, 0, rest.size / 2)
                body.flush()
                exchange.close()
            } else {
                body.write(rest)
                body.close()
            }
        }
        server.start()
    }

    @After
    fun stop() = server.stop(0)

    private fun url() = "http://127.0.0.1:${server.address.port}/apk"

    @Test
    fun wholeFileArrivesWhenNothingBreaks() = runBlocking {
        val directory = Files.createTempDirectory("qpvpn").toFile()
        val file = UpdateCheck.download(directory, url())

        assertNotNull("файл должен скачаться", file)
        assertEquals(content.size.toLong(), file!!.length())
        assertArrayEquals(content, file.readBytes())
    }

    @Test
    fun downloadContinuesAfterBreaks() = runBlocking {
        breakFirst = 3
        val directory = Files.createTempDirectory("qpvpn").toFile()
        val file = UpdateCheck.download(directory, url())

        assertNotNull("после обрывов файл всё равно должен собраться", file)
        assertEquals(content.size.toLong(), file!!.length())
        // Главное: куски склеились правильно, а не внахлёст и не с дырой.
        assertArrayEquals(content, file.readBytes())
        assertEquals("сервер должен был оборвать связь трижды", 3, breaks.get())
    }

    @Test
    fun nonApkIsRejected() = runBlocking {
        server.createContext("/notapk") { exchange ->
            val body = "<html>Ошибка</html>".toByteArray()
            exchange.sendResponseHeaders(200, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        val directory = Files.createTempDirectory("qpvpn").toFile()
        val file = UpdateCheck.download(directory, "http://127.0.0.1:${server.address.port}/notapk")

        assertNull("страница с ошибкой не должна сойти за сборку", file)
    }
}
