package kz.qpvpn

import kz.qpvpn.model.AppConfig
import kz.qpvpn.model.OwnRules
import kz.qpvpn.model.RuleKind
import kz.qpvpn.model.TunnelMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Поле «Свои сайты через VPN»: что человек впишет и что из этого выйдет.
 *
 * Те же проверки есть в версии для Mac: одно и то же поле на двух
 * устройствах должно понимать одно и то же.
 */
class OwnRulesTest {

    @Test
    fun domainBecomesRule() {
        val rules = OwnRules.parse("example.com")

        assertEquals(1, rules.size)
        assertEquals(RuleKind.DOMAIN, rules.first().kind)
        assertEquals("example.com", rules.first().value)
    }

    @Test
    fun networkBecomesRule() {
        val rules = OwnRules.parse("203.0.113.0/24")

        assertEquals(RuleKind.CIDR, rules.first().kind)
        assertEquals("203.0.113.0/24", rules.first().value)
    }

    @Test
    fun singleAddressIsAccepted() {
        assertEquals("198.51.100.7/32", OwnRules.parse("198.51.100.7").first().value)
    }

    @Test
    fun oneRulePerLine() {
        val rules = OwnRules.parse("example.com\nanother.org\n203.0.113.0/24")
        assertEquals(3, rules.size)
    }

    @Test
    fun commasSeparateToo() {
        assertEquals(2, OwnRules.parse("example.com, another.org").size)
    }

    @Test
    fun fullLinkIsUnderstood() {
        // Самое частое: скопировал из адресной строки браузера.
        assertEquals("example.com", OwnRules.parse("https://example.com/page?a=1").first().value)
        assertEquals("www.example.com", OwnRules.parse("http://www.example.com/").first().value)
    }

    @Test
    fun portIsDropped() {
        assertEquals("example.com", OwnRules.parse("example.com:8443").first().value)
    }

    @Test
    fun capitalsBecomeSmall() {
        assertEquals("example.com", OwnRules.parse("Example.COM").first().value)
    }

    @Test
    fun duplicatesAreNotRepeated() {
        val rules = OwnRules.parse("example.com\nEXAMPLE.COM\nhttps://example.com/page")
        assertEquals("одно и то же имя не должно попасть трижды", 1, rules.size)
    }

    @Test
    fun hashLineIsANote() {
        val rules = OwnRules.parse("# мои сайты\nexample.com")

        assertEquals(1, rules.size)
        assertEquals("example.com", rules.first().value)
    }

    @Test
    fun unreadableIsNotSwallowed() {
        // Опечатку надо показать, а не потерять.
        val text = "example.com\nэто не адрес"

        assertEquals(1, OwnRules.parse(text).size)
        assertEquals(listOf("это не адрес"), OwnRules.unreadable(text))
    }

    @Test
    fun correctTextHasNoComplaints() {
        assertTrue(OwnRules.unreadable("example.com\n203.0.113.0/24").isEmpty())
    }

    @Test
    fun emptyFieldIsNotAnError() {
        assertTrue(OwnRules.parse("").isEmpty())
        assertTrue(OwnRules.unreadable("   \n\n  ").isEmpty())
    }

    @Test
    fun textComesBackForTheField() {
        val text = "example.com\n203.0.113.0/24"
        assertEquals(text, OwnRules.text(OwnRules.parse(text)))
    }

    @Test
    fun ownRulesReachTheTunnel() {
        // Самое важное: вписанное человеком должно пойти через VPN.
        val config = AppConfig(rules = OwnRules.parse("my-service.example\n203.0.113.0/24"))

        val pinned = config.pinned()

        assertEquals(TunnelMode.INCLUDE, pinned.effectiveMode)
        assertTrue(pinned.activeRules.any { it.value == "my-service.example" })
        assertTrue(pinned.activeRules.any { it.value == "203.0.113.0/24" })
    }
}
