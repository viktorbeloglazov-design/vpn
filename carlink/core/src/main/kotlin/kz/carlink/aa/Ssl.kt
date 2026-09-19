package kz.carlink.aa

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.security.KeyStore
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.KeyManager
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLEngineResult
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * Шифрованный канал поверх сообщений SslHandshake.
 *
 * В Android Auto головное устройство — клиент TLS, телефон — сервер. Записи TLS
 * не идут отдельным потоком: они ездят внутри сообщений протокола, поэтому
 * вместо SSLSocket здесь SSLEngine, которому байты подают вручную.
 *
 * Сертификат другой стороны не проверяется: она на другом конце провода, а
 * цепочку Google всё равно проверить нечем. Зато он попадает в журнал — по нему
 * видно, что за устройство подключилось.
 *
 * @param clientMode сторона головного устройства (им пользуется эмулятор).
 */
class SslLink(keyManagers: Array<KeyManager>, clientMode: Boolean = false) : Cryptor {

    private val trust = RecordingTrustManager()

    private val engine: SSLEngine = SSLContext.getInstance("TLSv1.2").apply {
        init(keyManagers, arrayOf<TrustManager>(trust), SecureRandom())
    }.createSSLEngine().apply {
        useClientMode = clientMode
        // Машина показывает свой сертификат сама; требовать его мы не можем —
        // иначе разрыв там, где соединение могло бы состояться.
        if (!clientMode) wantClientAuth = true
        beginHandshake()
    }

    private var pending = ByteArray(0)
    private val buffered = ByteArrayOutputStream()

    val handshakeFinished: Boolean
        get() = engine.session.cipherSuite != "SSL_NULL_WITH_NULL_NULL"

    val cipherSuite: String
        get() = engine.session.cipherSuite

    /** Сертификат, который показала машина, — для журнала. */
    val peerCertificate: X509Certificate?
        get() = trust.peer

    /**
     * Первое слово в рукопожатии. Его говорит та сторона, что подключается, —
     * головное устройство. Телефон только отвечает, поэтому у него метод
     * возвращает пусто.
     */
    fun startHandshake(): ByteArray = drainWrap()

    /**
     * Принимает очередную порцию рукопожатия от машины.
     * Возвращает байты, которые надо отправить обратно (может быть пусто).
     */
    fun consumeHandshake(record: ByteArray): ByteArray {
        feed(record)
        val appData = unwrapAll()
        if (appData.isNotEmpty()) buffered.write(appData)
        return drainWrap()
    }

    override fun encrypt(plain: ByteArray): ByteArray {
        val src = ByteBuffer.wrap(plain)
        val out = ByteArrayOutputStream(plain.size + 64)
        while (src.hasRemaining()) {
            val dst = ByteBuffer.allocate(engine.session.packetBufferSize)
            val result = engine.wrap(src, dst)
            dst.flip()
            out.write(dst.toArray())
            runTasks()
            if (result.status != SSLEngineResult.Status.OK) {
                throw IllegalStateException("шифрование прервалось: ${result.status}")
            }
        }
        return out.toByteArray()
    }

    override fun decrypt(cipher: ByteArray): ByteArray {
        feed(cipher)
        val fresh = unwrapAll()
        if (buffered.size() == 0) return fresh
        buffered.write(fresh)
        val all = buffered.toByteArray()
        buffered.reset()
        return all
    }

    private fun feed(data: ByteArray) {
        pending = if (pending.isEmpty()) data else pending + data
    }

    private fun unwrapAll(): ByteArray {
        val app = ByteArrayOutputStream()
        val src = ByteBuffer.wrap(pending)
        while (src.hasRemaining()) {
            val dst = ByteBuffer.allocate(engine.session.applicationBufferSize)
            val result = engine.unwrap(src, dst)
            dst.flip()
            app.write(dst.toArray())
            runTasks()
            when (result.status) {
                SSLEngineResult.Status.BUFFER_UNDERFLOW -> break
                SSLEngineResult.Status.CLOSED -> break
                else -> Unit
            }
            if (result.bytesConsumed() == 0 && result.bytesProduced() == 0) break
        }
        pending = ByteArray(src.remaining()).also { src.get(it) }
        return app.toByteArray()
    }

    private fun drainWrap(): ByteArray {
        val out = ByteArrayOutputStream()
        while (engine.handshakeStatus == SSLEngineResult.HandshakeStatus.NEED_WRAP) {
            val dst = ByteBuffer.allocate(engine.session.packetBufferSize)
            val result = engine.wrap(EMPTY, dst)
            dst.flip()
            out.write(dst.toArray())
            runTasks()
            if (result.status != SSLEngineResult.Status.OK) break
        }
        return out.toByteArray()
    }

    private fun runTasks() {
        while (engine.handshakeStatus == SSLEngineResult.HandshakeStatus.NEED_TASK) {
            engine.delegatedTask?.run() ?: break
        }
    }

    private fun ByteBuffer.toArray(): ByteArray {
        val copy = ByteArray(remaining())
        get(copy)
        return copy
    }

    private class RecordingTrustManager : X509TrustManager {
        var peer: X509Certificate? = null

        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
            peer = chain?.firstOrNull()
        }

        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
            peer = chain?.firstOrNull()
        }

        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }

    companion object {
        private val EMPTY: ByteBuffer = ByteBuffer.allocate(0)
    }
}

/**
 * Загрузка ключа и цепочки из файла PKCS#12.
 *
 * Настоящая машина проверяет, что сертификат телефона подписан Google: так она
 * отличает телефон с Android Auto от чего угодно другого. Ни один ключ, который
 * можно сделать самому, эту проверку не пройдёт — он годится для эмулятора
 * головного устройства, где проверка выключена.
 */
object Pkcs12 {

    fun keyManagers(data: ByteArray, password: String): Array<KeyManager> {
        val store = KeyStore.getInstance("PKCS12")
        store.load(data.inputStream(), password.toCharArray())
        val factory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
        factory.init(store, password.toCharArray())
        return factory.keyManagers
    }
}
