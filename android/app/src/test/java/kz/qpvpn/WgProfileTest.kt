package kz.qpvpn

import kz.qpvpn.model.AppsMode
import kz.qpvpn.vpn.WgProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WgProfileTest {

    private val serverKey = "hK7mRb2QpS1vXzN9tYcLe4WgAqJdFu0iOs3BnVpM5xE="
    private val clientKey = "qZ4tGvB8nKdWx2Lp7YsEcRfT9uIoA1mHj3NbVy6XwQ0="

    private val sample = """
        [Interface]
        PrivateKey = $clientKey
        Address = 10.8.0.2/32
        DNS = 1.1.1.1, 8.8.8.8
        MTU = 1380

        [Peer]
        PublicKey = $serverKey
        Endpoint = 91.201.1.1:51820   # сервер в Алматы
        AllowedIPs = 0.0.0.0/0
        PersistentKeepalive = 25
    """.trimIndent()

    @Test
    fun parsesRealConfig() {
        val profile = WgProfile.parse(sample)
        assertEquals(clientKey, profile.privateKey)
        assertEquals(serverKey, profile.publicKey)
        assertEquals("91.201.1.1:51820", profile.endpoint)
        assertEquals(listOf("10.8.0.2/32"), profile.addresses)
        assertEquals(listOf("1.1.1.1", "8.8.8.8"), profile.dns)
        assertEquals(1380, profile.mtu)
        assertEquals(25, profile.keepalive)
        assertEquals("91.201.1.1", profile.endpointHost)
    }

    @Test(expected = WgProfile.Companion.ParseError::class)
    fun rejectsConfigWithoutPeer() {
        WgProfile.parse("[Interface]\nPrivateKey = $clientKey\nAddress = 10.8.0.2/32")
    }

    @Test(expected = WgProfile.Companion.ParseError::class)
    fun rejectsBrokenKey() {
        WgProfile.parse(sample.replace(clientKey, "не-ключ"))
    }

    @Test
    fun buildsConfigWithOurRoutesAndAppLists() {
        val profile = WgProfile.parse(sample)
        val text = profile.toConfigText(
            allowedIps = listOf("92.46.0.0/16", "5.35.96.12/32"),
            includeDns = false,
            appsMode = AppsMode.EXCEPT_SELECTED,
            apps = listOf("ru.sberbankmobile", "ru.wildberries"),
        )

        assertTrue(text.contains("AllowedIPs = 92.46.0.0/16, 5.35.96.12/32"))
        assertTrue(text.contains("ExcludedApplications = ru.sberbankmobile, ru.wildberries"))
        assertTrue(!text.contains("DNS ="))
        assertTrue(text.contains("Endpoint = 91.201.1.1:51820"))
    }
}
