package kz.qpvpn

import kotlinx.coroutines.runBlocking
import kz.qpvpn.net.UpdateCheck
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.Socket
import java.nio.file.Files
import java.util.concurrent.atomic.AtomicInteger

/**
 * Докачка после обрыва.
 *
 * Сборки раздаются с адреса, который в России режется: связь рвётся
 * посередине большого файла. Закачка с нуля в таком канале не доходит
 * никогда, поэтому приложение обязано продолжать с места обрыва.
 *
 * Поднимаем свой сервер, который честно рвёт связь, и проверяем, что файл
 * всё равно собирается целиком и побайтово совпадает с исходным.
 */
class ResumeDownloadTest {

    /** «PK» в начале — как у настоящего APK, дальше узнаваемый мусор. */
    private val content = ByteArray(300_000) { index ->
        when (index) {
            0 -> 'P'.code.toByte()
            1 -> 'K'.code.toByte()
            else -> (index % 251).toByte()
        }
    }

    private lateinit var socket: ServerSocket
    private lateinit var worker: Thread

    /** Сколько первых ответов оборвать на середине. */
    @Volatile private var breakFirst = 0

    /** Отдавать вместо сборки страницу с ошибкой. */
    @Volatile private var serveGarbage = false

    private val breaks = AtomicInteger(0)

    @Before
    fun start() {
        socket = ServerSocket(0)
        worker = Thread {
            while (!socket.isClosed) {
                try {
                    socket.accept().use(::serve)
                } catch (error: Exception) {
                    return@Thread
                }
            }
        }
        worker.isDaemon = true
        worker.start()
    }

    @After
    fun stop() {
        socket.close()
        worker.join(2_000)
    }

    /** Минимальный HTTP: разбираем Range и отвечаем куском файла. */
    private fun serve(client: Socket) {
        val reader = BufferedReader(InputStreamReader(client.getInputStream()))
        var from = 0
        while (true) {
            val line = reader.readLine() ?: break
            if (line.isEmpty()) break
            if (line.startsWith("Range:", ignoreCase = true)) {
                from = line.substringAfter("bytes=").substringBefore('-').trim().toIntOrNull() ?: 0
            }
        }

        val output = client.getOutputStream()
        if (serveGarbage) {
            val body = "<html>Ошибка</html>".toByteArray()
            output.write(head(200, body.size).toByteArray())
            output.write(body)
            output.flush()
            return
        }

        val rest = content.copyOfRange(from, content.size)
        output.write(head(if (from > 0) 206 else 200, rest.size).toByteArray())

        if (breaks.get() < breakFirst) {
            // Обещали целое, отдаём половину и обрываем — ровно так ведёт
            // себя канал, из-за которого всё это и понадобилось.
            breaks.incrementAndGet()
            output.write(rest, 0, rest.size / 2)
            output.flush()
            client.close()
            return
        }

        output.write(rest)
        output.flush()
    }

    private fun head(code: Int, length: Int) = buildString {
        append("HTTP/1.1 $code OK\r\n")
        append("Content-Length: $length\r\n")
        append("ETag: \"qpvpn-test\"\r\n")
        append("Connection: close\r\n\r\n")
    }

    private fun url() = "http://127.0.0.1:${socket.localPort}/apk"

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
        // Главное: куски склеились правильно — не внахлёст и не с дырой.
        assertArrayEquals(content, file.readBytes())
        assertEquals("связь должна была оборваться трижды", 3, breaks.get())
    }

    @Test
    fun errorPageIsNotAccepted() = runBlocking {
        serveGarbage = true
        val directory = Files.createTempDirectory("qpvpn").toFile()
        val file = UpdateCheck.download(directory, url())

        assertNull("страница с ошибкой не должна сойти за сборку", file)
    }
}
