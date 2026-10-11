package kz.qpvpn

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kz.qpvpn.vpn.XrayLink
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

/** Ключи X-Ray на Android. Все данные выдуманы: репозиторий публичный. */
class XrayLinkTest {

    private val uuid = "00000000-0000-4000-8000-000000000000"
    private val reality = "vless://$uuid@203.0.113.10:443?encryption=none&flow=xtls-rprx-vision" +
        "&security=reality&sni=www.example.com&fp=chrome&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
        "&sid=0123abcd&spx=%2F&type=tcp#QP%20VPN%20KZ"

    @Test
    fun realityРазбирается() {
        val link = XrayLink.parse(reality)
        assertEquals(XrayLink.Kind.VLESS, link.kind)
        assertEquals("203.0.113.10", link.host)
        assertEquals(443, link.port)
        assertEquals("xtls-rprx-vision", link.flow)
        assertEquals("reality", link.security)
        assertEquals("/", link.spiderX)
        assertEquals("QP VPN KZ", link.name)
        assertEquals("X-Ray (VLESS Reality)", link.title)
    }

    @Test
    fun ключНаходитсяВнутриПисьма() {
        val letter = "Ваш ключ:\n\n  $reality  \n\nВставьте его."
        assertTrue(XrayLink.looksLikeLink(letter))
        assertEquals("203.0.113.10", XrayLink.parse(letter).host)
    }

    @Test(expected = IllegalArgumentException::class)
    fun realityБезКлючаНеПринимается() {
        XrayLink.parse("vless://$uuid@203.0.113.10:443?security=reality&sni=www.example.com")
    }

    @Test
    fun троянСПлюсомВПароле() {
        val link = XrayLink.parse("trojan://pa+ss@vpn.example.com:443?sni=vpn.example.com")
        assertEquals("pa+ss", link.secret)
        assertEquals("tls", link.security)
    }

    @Test
    fun vmessИShadowsocks() {
        val json = """{"add":"203.0.113.20","port":"443","id":"$uuid","net":"ws","path":"/v","tls":"tls"}"""
        val vmess = XrayLink.parse("vmess://" + Base64.getEncoder().encodeToString(json.toByteArray()))
        assertEquals(XrayLink.Kind.VMESS, vmess.kind)
        assertEquals("ws", vmess.network)

        val info = Base64.getEncoder().encodeToString("chacha20-ietf-poly1305:pass123".toByteArray())
        val ss = XrayLink.parse("ss://$info@203.0.113.30:8388#SS")
        assertEquals("chacha20-ietf-poly1305", ss.method)
        assertEquals("pass123", ss.secret)
    }

    @Test
    fun запасной_входМеняетТолькоАдрес() {
        val link = XrayLink.parse(reality).withEndpoint("198.51.100.5:8443")
        assertEquals("198.51.100.5", link.host)
        assertEquals(8443, link.port)
        assertEquals(uuid, link.secret)
    }

    @Test
    fun настройкиXray() {
        val config = Json.parseToJsonElement(XrayLink.parse(reality).toConfigJson()).jsonObject
        val inbound = config["inbounds"]!!.jsonArray[0].jsonObject
        assertEquals("127.0.0.1", inbound["listen"]!!.jsonPrimitive.content)
        assertEquals("true", inbound["settings"]!!.jsonObject["udp"]!!.jsonPrimitive.content)
        val outbound = config["outbounds"]!!.jsonArray[0].jsonObject
        assertEquals("vless", outbound["protocol"]!!.jsonPrimitive.content)
        val reality = outbound["streamSettings"]!!.jsonObject["realitySettings"]!!.jsonObject
        assertEquals("www.example.com", reality["serverName"]!!.jsonPrimitive.content)
    }
}
