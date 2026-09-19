import XCTest
@testable import KupibasCore

final class ConfigTests: XCTestCase {

    private func makeServer() -> ServerConfig {
        ServerConfig(name: "KZ",
                     endpoint: "91.201.1.1:51820",
                     publicKey: Data(repeating: 1, count: 32).base64EncodedString(),
                     presharedKey: "",
                     privateKey: Data(repeating: 2, count: 32).base64EncodedString(),
                     addresses: ["10.8.0.2/32"],
                     dns: ["1.1.1.1"])
    }

    func testServerValidation() {
        XCTAssertNil(makeServer().validationError)

        var noKey = makeServer()
        noKey.privateKey = ""
        XCTAssertNotNil(noKey.validationError)

        var badEndpoint = makeServer()
        badEndpoint.endpoint = "91.201.1.1"
        XCTAssertNotNil(badEndpoint.validationError)

        var badMTU = makeServer()
        badMTU.mtu = 9000
        XCTAssertNotNil(badMTU.validationError)
    }

    func testRulesSignatureIgnoresOrderAndDisabledRules() {
        var config = TunnelConfig(server: makeServer())
        config.rules = [
            RoutingRule(kind: .domain, value: "kaspi.kz"),
            RoutingRule(kind: .cidr, value: "10.0.0.0/8"),
        ]
        let first = config.rulesSignature

        config.rules.reverse()
        XCTAssertEqual(first, config.rulesSignature, "порядок правил не должен вызывать перенастройку")

        config.rules.append(RoutingRule(kind: .domain, value: "egov.kz", enabled: false))
        XCTAssertEqual(first, config.rulesSignature, "выключенное правило не влияет на маршруты")

        config.rules.append(RoutingRule(kind: .domain, value: "egov.kz"))
        XCTAssertNotEqual(first, config.rulesSignature)
    }

    func testRestartSignatureReactsToConnectionChanges() {
        var config = TunnelConfig(server: makeServer())
        let baseline = config.restartSignature

        config.rules = [RoutingRule(kind: .domain, value: "kaspi.kz")]
        XCTAssertEqual(baseline, config.restartSignature, "правила не требуют перезапуска туннеля")

        // Подпись считается по тому, что применяется на самом деле.
        // При включённом главном фильтре режим в расширенных настройках
        // ничего не меняет — значит, и перезапускать нечего.
        config.mode = .include
        XCTAssertEqual(baseline, config.restartSignature, "главный фильтр перекрывает режим")

        config.mainFilter = false
        XCTAssertNotEqual(baseline, config.restartSignature, "без главного фильтра режим снова решает")

        var all = TunnelConfig(server: makeServer())
        all.fullTunnel = true
        XCTAssertNotEqual(baseline, all.restartSignature, "весь трафик — это другой туннель")

        var other = TunnelConfig(server: makeServer())
        other.server.endpoint = "91.201.1.2:51820"
        XCTAssertNotEqual(baseline, other.restartSignature)
    }

    func testSwitchesChangeRoutesWithoutRestart() {
        var config = TunnelConfig(server: makeServer())
        let routes = config.rulesSignature

        config.workFilter = false
        XCTAssertNotEqual(routes, config.rulesSignature, "рабочие ресурсы меняют набор исключений")
        XCTAssertEqual(TunnelConfig(server: makeServer()).restartSignature,
                       config.restartSignature,
                       "переключатель рабочих ресурсов не требует перезапуска туннеля")
    }

    func testDecodingToleratesMissingFields() throws {
        let json = Data("""
        {"enabled": true, "mode": "exclude"}
        """.utf8)
        let config = try JSONDecoder().decode(TunnelConfig.self, from: json)
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.mode, .exclude)
        XCTAssertEqual(config.options.reresolveMinutes, 5)
        XCTAssertEqual(config.server.mtu, 1420)
        XCTAssertTrue(config.rules.isEmpty)
    }

    func testAtomicWriteRoundTrip() throws {
        let directory = NSTemporaryDirectory() + "kupibas-vpn-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let path = directory + "/config.json"
        var config = TunnelConfig(enabled: true, mode: .include, server: makeServer())
        config.rules = [RoutingRule(kind: .domain, value: "kaspi.kz")]

        let data = try JSONEncoder().encode(config)
        try ConfigStore.writeAtomically(data: data, to: path, permissions: 0o660)
        try ConfigStore.writeAtomically(data: data, to: path, permissions: 0o660)

        let loaded = try JSONDecoder().decode(TunnelConfig.self,
                                              from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(loaded, config)

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.int16Value, 0o660)
    }

    func testPresetsAreValid() {
        XCTAssertFalse(Presets.all.isEmpty)
        for preset in Presets.all {
            XCTAssertFalse(preset.rules.isEmpty, preset.title)
            for rule in preset.rules {
                XCTAssertNil(Validation.ruleError(kind: rule.kind, value: rule.value),
                             "\(preset.title): \(rule.value)")
            }
        }
    }

    func testFormatting() {
        XCTAssertEqual(Formatting.bytes(512), "512 Б")
        XCTAssertEqual(Formatting.bytes(2048), "2.0 КБ")
        XCTAssertEqual(Formatting.relative(0), "—")
        XCTAssertEqual(Formatting.duration(since: 0), "—")
    }
}
