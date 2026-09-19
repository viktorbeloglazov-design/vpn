package kz.carlink

import kz.carlink.aa.Credentials
import kz.carlink.aa.SslLink
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLEngineResult
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * Проверяет слой TLS без машины: с одной стороны [SslLink], с другой — обычный
 * клиент JSSE, как головное устройство. Ключ для проверки лежит в ресурсах
 * теста, настоящий сертификат для машины к нему отношения не имеет.
 */
class SslHandshakeTest {

    private val trustAll = object : X509TrustManager {
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
        override fun getAcceptedIssuers() = emptyArray<X509Certificate>()
    }

    private fun pump(engine: SSLEngine, incoming: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        var src = ByteBuffer.wrap(incoming)
        while (true) {
            var progressed = false
            if (src.hasRemaining()) {
                val dst = ByteBuffer.allocate(engine.session.applicationBufferSize)
                val r = engine.unwrap(src, dst)
                if (r.bytesConsumed() > 0 || r.bytesProduced() > 0) progressed = true
                if (r.status == SSLEngineResult.Status.BUFFER_UNDERFLOW) src = ByteBuffer.allocate(0)
            }
            while (engine.handshakeStatus == SSLEngineResult.HandshakeStatus.NEED_TASK) {
                engine.delegatedTask?.run(); progressed = true
            }
            if (engine.handshakeStatus == SSLEngineResult.HandshakeStatus.NEED_WRAP) {
                val dst = ByteBuffer.allocate(engine.session.packetBufferSize)
                engine.wrap(ByteBuffer.allocate(0), dst)
                dst.flip()
                val b = ByteArray(dst.remaining()); dst.get(b); out.write(b)
                progressed = true
            }
            if (!progressed) break
        }
        return out.toByteArray()
    }

    @Test
    fun handshakeCompletesAndDataFlows() {
        val p12 = javaClass.classLoader!!.getResourceAsStream("handshake-test.p12")!!.use { it.readBytes() }
        val keyManagers = Credentials.fromPkcs12(p12, "secret")
        val server = SslLink(keyManagers)

        val context = SSLContext.getInstance("TLSv1.2")
        context.init(null, arrayOf<TrustManager>(trustAll), SecureRandom())
        val client = context.createSSLEngine().apply { useClientMode = true; beginHandshake() }

        var toServer = pump(client, ByteArray(0))
        var rounds = 0
        while (!server.handshakeFinished && rounds++ < 12) {
            val toClient = server.consumeHandshake(toServer)
            toServer = pump(client, toClient)
            if (toServer.isEmpty() && toClient.isEmpty()) break
        }
        if (toServer.isNotEmpty()) server.consumeHandshake(toServer)

        println("рукопожатие за $rounds кругов, шифр ${server.cipherSuite}")
        assertTrue("рукопожатие не завершилось", server.handshakeFinished)

        // Телефон -> машина
        val payload = ByteArray(40_000) { (it % 251).toByte() }
        val encrypted = server.encrypt(payload)
        val dst = ByteBuffer.allocate(payload.size + 4096)
        val src = ByteBuffer.wrap(encrypted)
        while (src.hasRemaining()) client.unwrap(src, dst)
        dst.flip()
        val received = ByteArray(dst.remaining()); dst.get(received)
        assertArrayEquals(payload, received)

        // Машина -> телефон
        val answer = "ответ машины".toByteArray()
        val net = ByteBuffer.allocate(client.session.packetBufferSize)
        client.wrap(ByteBuffer.wrap(answer), net)
        net.flip()
        val netBytes = ByteArray(net.remaining()); net.get(netBytes)
        assertArrayEquals(answer, server.decrypt(netBytes))
    }
}
