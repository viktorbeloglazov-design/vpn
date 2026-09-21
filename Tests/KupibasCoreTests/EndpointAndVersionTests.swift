import XCTest
@testable import KupibasCore

/// Запасной вход и сравнение версий — то же, что в версии для телефона.
final class EndpointAndVersionTests: XCTestCase {

    private func makeConfig(backup: String = "") -> TunnelConfig {
        var config = TunnelConfig(backupEndpoint: backup)
        config.server.endpoint = "77.240.39.23:31984"
        return config
    }

    func testWithoutBackupThereIsOnlyTheServer() {
        XCTAssertEqual(makeConfig().endpointsToTry(), ["77.240.39.23:31984"])
    }

    func testServerGoesFirstAndBackupSecond() {
        XCTAssertEqual(makeConfig(backup: "95.213.0.1:443").endpointsToTry(),
                       ["77.240.39.23:31984", "95.213.0.1:443"])
    }

    func testSpacesAroundTheAddressDoNotCount() {
        XCTAssertEqual(makeConfig(backup: "  95.213.0.1:443  ").endpointsToTry(),
                       ["77.240.39.23:31984", "95.213.0.1:443"])
    }

    func testTheSameAddressIsNotTriedTwice() {
        // Иначе при молчащем сервере человек ждал бы вдвое дольше впустую.
        XCTAssertEqual(makeConfig(backup: "77.240.39.23:31984").endpointsToTry(),
                       ["77.240.39.23:31984"])
    }

    func testBackupAndProbedMtuSurvivePinning() {
        // Маршрутизация зашита, а адрес входа и подобранный размер пакета —
        // это не маршрутизация: они обязаны пережить приведение к заводскому.
        var config = makeConfig(backup: "95.213.0.1:443")
        config.options.probedMtu = 1320
        let pinned = config.pinned()

        XCTAssertEqual(pinned.backupEndpoint, "95.213.0.1:443")
        XCTAssertEqual(pinned.options.probedMtu, 1320)
    }

    func testChangingTheBackupRebuildsTheTunnel() {
        // Иначе новый адрес не вступит в силу, пока не выключить и включить.
        var config = makeConfig()
        let before = config.restartSignature
        config.backupEndpoint = "95.213.0.1:443"
        XCTAssertNotEqual(before, config.restartSignature)
    }
}
