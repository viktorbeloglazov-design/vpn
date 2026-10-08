import XCTest
@testable import KupibasCore

/// Gmail — мимо VPN, хотя живёт в сетях Google, которые идут в туннель.
final class GmailDirectTests: XCTestCase {

    func testАдресGmailИдётНапрямую() {
        let nets = VpnServices.directNets(gmailAddresses: ["142.250.74.37"],
                                          tunnelRoutes: ["142.250.0.0/15"])
        XCTAssertEqual(nets.map(\.text), ["142.250.74.37/32"],
                       "точный маршрут мимо туннеля важнее широкой сети Google")
    }

    func testАдресОбщийСYouTubeОстаётсяВVPN() {
        // DNS может назвать для почты тот же адрес, что и для YouTube.
        // Пусти его напрямую — вместе с почтой мимо VPN уйдёт YouTube.
        let nets = VpnServices.directNets(gmailAddresses: ["142.250.74.14", "142.250.74.37"],
                                          tunnelRoutes: ["142.250.0.0/15", "142.250.74.14/32"])
        XCTAssertEqual(nets.map(\.text), ["142.250.74.37/32"])
    }

    func testIPv6ИЧастныеАдресаНеБерутся() {
        let nets = VpnServices.directNets(gmailAddresses: ["2a00:1450:4010:c05::11", "10.0.0.1",
                                                           "127.0.0.1", "142.250.74.37"],
                                          tunnelRoutes: [])
        XCTAssertEqual(nets.map(\.text), ["142.250.74.37/32"],
                       "заглушка провайдера или частный адрес — не повод прокладывать маршрут")
    }

    func testПовторыСхлопываются() {
        let nets = VpnServices.directNets(gmailAddresses: ["142.250.74.37", "142.250.74.37"],
                                          tunnelRoutes: [])
        XCTAssertEqual(nets.count, 1)
    }

    func testВСпискеИменаПочтыАНеYouTube() {
        XCTAssertTrue(VpnServices.directDomains.contains("mail.google.com"))
        XCTAssertTrue(VpnServices.directDomains.contains("imap.gmail.com"),
                      "почтовые программы ходят по IMAP и SMTP, не через сайт")
        XCTAssertTrue(VpnServices.directDomains.contains("smtp.gmail.com"))
        for domain in VpnServices.directDomains {
            XCTAssertTrue(Validation.isDomain(domain), domain)
            XCTAssertFalse(domain.contains("youtube") || domain.contains("googlevideo")
                           || domain.contains("gemini"),
                           "\(domain): мимо VPN не должно уходить то, ради чего он включён")
        }
    }

    func testИменаGmailНеЗаявленыВТуннель() {
        let tunnelDomains = Set(VpnServices.rules().filter { $0.kind == .domain }.map(\.value))
        for domain in VpnServices.directDomains {
            XCTAssertFalse(tunnelDomains.contains(domain), "\(domain) одновременно и в VPN, и мимо")
        }
    }
}
