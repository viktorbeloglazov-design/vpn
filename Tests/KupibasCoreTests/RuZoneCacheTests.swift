import XCTest
@testable import KupibasCore

/// Чтение списка российских подсетей.
///
/// По этому списку строится обход: всё, что в нём, идёт мимо туннеля.
/// Пустой список означает, что банки, госуслуги и МАХ уйдут через VPN
/// и увидят казахстанский адрес — то есть ровно то, чего быть не должно.
final class RuZoneCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RuZone.reload()
    }

    override func tearDown() {
        RuZone.reload()
        super.tearDown()
    }

    func testПустотаНеЗапоминается() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let path = directory.appendingPathComponent("ru_ipv4.txt").path

        // Файла ещё нет: служба обратилась к списку раньше установщика.
        XCTAssertTrue(RuZone.networks(extraPaths: [path]).isEmpty)

        // Установщик положил файл. Список должен прочитаться, а не остаться
        // пустым до перезапуска службы.
        try "5.8.0.0/19\n5.16.0.0/14\n".write(toFile: path, atomically: true, encoding: .utf8)

        let nets = RuZone.networks(extraPaths: [path])
        XCTAssertEqual(nets.count, 2, "список должен прочитаться, как только появился")
    }

    func testПрочитанныйСписокНеПеречитываетсяКаждыйРаз() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let path = directory.appendingPathComponent("ru_ipv4.txt").path
        try "5.8.0.0/19\n".write(toFile: path, atomically: true, encoding: .utf8)

        XCTAssertEqual(RuZone.networks(extraPaths: [path]).count, 1)

        // Файл убрали — но однажды прочитанный список остаётся в памяти:
        // перечитывать девять тысяч строк на каждом такте незачем.
        try FileManager.default.removeItem(atPath: path)
        XCTAssertEqual(RuZone.networks(extraPaths: [path]).count, 1)
    }

    func testМусорныеСтрокиПропускаются() {
        let nets = RuZone.parse("""
            # комментарий
            5.8.0.0/19

            не адрес
            5.16.0.0/14
            """)

        XCTAssertEqual(nets.count, 2)
    }

    func testПустойТекстДаётПустойСписок() {
        XCTAssertTrue(RuZone.parse("").isEmpty)
        XCTAssertTrue(RuZone.parse("\n\n# только комментарий\n").isEmpty)
    }
}
