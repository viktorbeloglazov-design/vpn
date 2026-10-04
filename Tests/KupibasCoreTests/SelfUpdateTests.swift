import XCTest
@testable import KupibasCore

/// Служба обновляет себя сама: когда проверять и что принимать.
final class SelfUpdateTests: XCTestCase {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - Когда проверять

    func testСразуПослеЗапускаНеПроверяет() {
        XCTAssertFalse(SelfUpdate.isDue(sinceStart: 30, sinceLastCheck: nil, requested: false),
                       "сначала туннель, потом обновления")
    }

    func testПервыйРазПроверяетЧерезДвеМинуты() {
        XCTAssertTrue(SelfUpdate.isDue(sinceStart: 121, sinceLastCheck: nil, requested: false))
    }

    func testДальшеРазВТриЧаса() {
        XCTAssertFalse(SelfUpdate.isDue(sinceStart: 9_000, sinceLastCheck: 2 * 3600, requested: false))
        XCTAssertTrue(SelfUpdate.isDue(sinceStart: 20_000, sinceLastCheck: 3 * 3600, requested: false))
    }

    func testПослеНеудачиПробуетРаньше() {
        XCTAssertTrue(SelfUpdate.isDue(sinceStart: 9_000, sinceLastCheck: 31 * 60,
                                       lastFailed: true, requested: false))
        XCTAssertFalse(SelfUpdate.isDue(sinceStart: 9_000, sinceLastCheck: 10 * 60,
                                        lastFailed: true, requested: false))
    }

    func testПросьбаПриложенияПроверяетСразу() {
        XCTAssertTrue(SelfUpdate.isDue(sinceStart: 5, sinceLastCheck: 60, requested: true),
                      "человек нажал «Обновить» — ждать три часа нельзя")
    }

    // MARK: - Какая служба умеет сама

    func testСамаОбновляетсяСлужбаНачинаяС370() {
        XCTAssertTrue(SelfUpdate.selfUpdates(helperVersion: "3.7.0"))
        XCTAssertTrue(SelfUpdate.selfUpdates(helperVersion: "3.10.0"))
        XCTAssertTrue(SelfUpdate.selfUpdates(helperVersion: "4.0"))
    }

    func testСтараяСлужбаСамаНеУмеет() {
        // Такой её последний раз обновляет приложение, с паролем.
        XCTAssertFalse(SelfUpdate.selfUpdates(helperVersion: "3.6.1"))
        XCTAssertFalse(SelfUpdate.selfUpdates(helperVersion: "3.5.1"))
        XCTAssertFalse(SelfUpdate.selfUpdates(helperVersion: nil))
        XCTAssertFalse(SelfUpdate.selfUpdates(helperVersion: ""))
    }

    // MARK: - Номера версий

    func testНомераСравниваютсяЧислами() {
        XCTAssertTrue(Versions.isNewer("3.10.0", than: "3.9.9"))
        XCTAssertTrue(Versions.isNewer("3.7.0", than: "3.6.1"))
        XCTAssertFalse(Versions.isNewer("3.6.1", than: "3.6.1"))
        XCTAssertFalse(Versions.isNewer("3.6", than: "3.6.0"))
    }

    func testСтраницаОшибкиЗаВерсиюНеСойдёт() {
        XCTAssertTrue(Versions.isPlausible("3.7.0"))
        XCTAssertTrue(Versions.isPlausible(" 3.7.0\n"))
        XCTAssertFalse(Versions.isPlausible(""))
        XCTAssertFalse(Versions.isPlausible("Not Found"))
        XCTAssertFalse(Versions.isPlausible("<html>"))
        XCTAssertFalse(Versions.isPlausible("3.7."))
        XCTAssertFalse(Versions.isPlausible("3.7.0; rm -rf /"))
    }

    // MARK: - Что принимать из образа

    private let full: Set<String> = ["kupibasvpnd", "amneziawg-go", "awg", "wireguard-go", "wg"]

    func testНашеПриложениеНужнойВерсииПринимается() {
        XCTAssertNil(SelfUpdate.problem(bundleIdentifier: "com.kupibas.vpn",
                                        bundleVersion: "3.7.0",
                                        expectedVersion: "3.7.0",
                                        presentHelperFiles: full))
    }

    func testЧужоеПриложениеНеСтавится() {
        XCTAssertNotNil(SelfUpdate.problem(bundleIdentifier: "com.example.other",
                                           bundleVersion: "3.7.0",
                                           expectedVersion: "3.7.0",
                                           presentHelperFiles: full))
        XCTAssertNotNil(SelfUpdate.problem(bundleIdentifier: nil,
                                           bundleVersion: "3.7.0",
                                           expectedVersion: "3.7.0",
                                           presentHelperFiles: full))
    }

    func testВерсияВОбразеДолжнаСовпастьСОбъявленной() {
        // Иначе служба поставит одно, запишет другое — и будет
        // скачивать себя по кругу каждые три часа.
        XCTAssertNotNil(SelfUpdate.problem(bundleIdentifier: "com.kupibas.vpn",
                                           bundleVersion: "3.6.1",
                                           expectedVersion: "3.7.0",
                                           presentHelperFiles: full))
    }

    func testБезСлужбыИлиТуннеляНеСтавится() {
        XCTAssertNotNil(SelfUpdate.problem(bundleIdentifier: "com.kupibas.vpn",
                                           bundleVersion: "3.7.0",
                                           expectedVersion: "3.7.0",
                                           presentHelperFiles: ["amneziawg-go", "wg"]))
        XCTAssertNotNil(SelfUpdate.problem(bundleIdentifier: "com.kupibas.vpn",
                                           bundleVersion: "3.7.0",
                                           expectedVersion: "3.7.0",
                                           presentHelperFiles: ["kupibasvpnd", "wg"]))
    }

    // MARK: - Пути

    func testСкачанноеЛежитВЗакрытойПапкеСлужбы() {
        // Папка настроек открыта на запись обычному пользователю.
        // Положи служба скачанное туда — подменить его мог бы кто угодно.
        XCTAssertTrue(SelfUpdate.workDir.hasPrefix(Paths.helperDir + "/"))
        XCTAssertFalse(SelfUpdate.workDir.hasPrefix(Paths.stateDir))
    }

    func testСсылкиТеЖеЧтоИУПриложения() {
        XCTAssertEqual(SelfUpdate.versionURL.absoluteString,
                       "https://github.com/viktorbeloglazov-design/vpn/releases/download/latest/mac-version.txt")
        XCTAssertEqual(SelfUpdate.imageURL.absoluteString,
                       "https://github.com/viktorbeloglazov-design/vpn/releases/download/latest/QPVPN-mac.dmg")
    }

    func testОпознавательныйЗнакСовпадаетСИнфо() throws {
        let plist = try String(contentsOf: repositoryRoot.appendingPathComponent("Resources/Info.plist"),
                               encoding: .utf8)
        XCTAssertTrue(plist.contains("<string>\(SelfUpdate.bundleIdentifier)</string>"),
                      "служба сверяет образ с этим знаком — он обязан совпадать с приложением")
    }
}
