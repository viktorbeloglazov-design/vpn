package kz.qpvpn

import kz.qpvpn.vpn.AmneziaLink
import kz.qpvpn.vpn.WgProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.Base64
import java.util.zip.Deflater

/** Проверки разбора того, чем делится Amnezia: ссылка vpn://, QR, файл. */
class AmneziaLinkTest {

    private val clientKey = "qZ4tGvB8nKdWx2Lp7YsEcRfT9uIoA1mHj3NbVy6XwQ0="
    private val serverKey = "hK7mRb2QpS1vXzN9tYcLe4WgAqJdFu0iOs3BnVpM5xE="

    private val awgConfig = """
        [Interface]
        Address = 10.8.1.2/32
        DNS = 1.1.1.1
        PrivateKey = $clientKey
        Jc = 4
        Jmin = 40
        Jmax = 70
        S1 = 50
        S2 = 100
        H1 = 1234567890
        H2 = 987654321
        H3 = 555555555
        H4 = 444444444

        [Peer]
        PublicKey = $serverKey
        AllowedIPs = 0.0.0.0/0
        Endpoint = 91.201.14.77:41820
        PersistentKeepalive = 25
    """.trimIndent()

    /** Повторяем упаковку Amnezia: JSON со строкой настроек, zlib, размер впереди, base64. */
    private fun amneziaLink(config: String): String {
        val json = """
            {"containers":[{"container":"amnezia-awg","awg":{"last_config":
            "{\"H1\":\"1234567890\",\"config\":\"${config.replace("\n", "\\n").replace("\"", "\\\"")}\"}"}}],
            "defaultContainer":"amnezia-awg","hostName":"91.201.14.77"}
        """.trimIndent()

        val source = json.toByteArray(Charsets.UTF_8)
        val deflater = Deflater()
        deflater.setInput(source)
        deflater.finish()
        val packed = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (!deflater.finished()) {
            packed.write(buffer, 0, deflater.deflate(buffer))
        }
        deflater.end()

        val header = ByteBuffer.allocate(4).putInt(source.size).array()
        val payload = header + packed.toByteArray()
        return "vpn://" + Base64.getUrlEncoder().withoutPadding().encodeToString(payload)
    }

    @Test
    fun readsPlainConfigFile() {
        val result = AmneziaLink.extractConfig(awgConfig)
        assertNotNull(result)
        assertTrue(result!!.startsWith("[Interface]"))
        assertTrue(result.contains("Jc = 4"))
    }

    @Test
    fun readsAmneziaShareLink() {
        val link = amneziaLink(awgConfig)
        val result = AmneziaLink.extractConfig(link)

        assertNotNull("ссылка vpn:// должна разворачиваться", result)
        val profile = WgProfile.parse(result!!)
        assertEquals("91.201.14.77:41820", profile.endpoint)
        assertEquals(clientKey, profile.privateKey)
        assertEquals(serverKey, profile.publicKey)
    }

    @Test
    fun keepsMaskingParametersFromAmnezia() {
        val result = AmneziaLink.extractConfig(amneziaLink(awgConfig))
        val profile = WgProfile.parse(result!!)

        assertTrue("профиль должен опознаться как AmneziaWG", profile.isAmnezia)
        assertEquals("AmneziaWG", profile.protocolName)
        assertEquals("4", profile.amneziaParams["jc"])
        assertEquals("100", profile.amneziaParams["s2"])
        assertEquals("1234567890", profile.amneziaParams["h1"])
    }

    @Test
    fun masksSurviveRoundTripToTunnelConfig() {
        val profile = WgProfile.parse(AmneziaLink.extractConfig(amneziaLink(awgConfig))!!)
        val text = profile.toConfigText(
            allowedIps = listOf("0.0.0.0/0"),
            includeDns = true,
            appsMode = kz.qpvpn.model.AppsMode.OFF,
            apps = emptyList(),
        )

        assertTrue(text.contains("Jc = 4"))
        assertTrue(text.contains("H4 = 444444444"))
        assertTrue(text.contains("AllowedIPs = 0.0.0.0/0"))
    }

    @Test
    fun ignoresNonsense() {
        assertNull(AmneziaLink.extractConfig(""))
        assertNull(AmneziaLink.extractConfig("вот вам ссылка на котиков"))
        assertNull(AmneziaLink.extractConfig("vpn://не-база64!!!"))
    }
}

/** Отдельно: программа должна уметь назвать протокол, которого не понимает. */
class AmneziaProtocolTest {

    @Test
    fun namesOpenVpnContainer() {
        val json = """{"containers":[{"container":"amnezia-openvpn"}],"defaultContainer":"amnezia-openvpn"}"""
        assertEquals("OpenVPN", kz.qpvpn.vpn.AmneziaLink.describeProtocol(json))
    }

    @Test
    fun namesXrayContainer() {
        val json = """{"defaultContainer":"amnezia-xray","containers":[{"container":"amnezia-xray"}]}"""
        assertEquals("XRay (VLESS Reality)", kz.qpvpn.vpn.AmneziaLink.describeProtocol(json))
    }

    @Test
    fun namesShadowsocksLink() {
        assertEquals("Shadowsocks", kz.qpvpn.vpn.AmneziaLink.describeProtocol("ss://Y2hhY2hh@1.2.3.4:8388"))
    }

    @Test
    fun saysNothingAboutPlainText() {
        assertNull(kz.qpvpn.vpn.AmneziaLink.describeProtocol("просто текст"))
    }
}
