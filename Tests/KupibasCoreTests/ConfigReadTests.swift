import XCTest
@testable import KupibasCore

/// Чтение настроек службой.
///
/// Здесь проверяется то, из-за чего связь на Mac отваливалась сама собой.
/// Служба раз в секунду читает файл настроек. Раньше любая осечка чтения
/// давала пустые настройки, а в них VPN выключен, — и служба молча
/// опускала рабочий туннель. После этого маршрут по умолчанию оставался
/// ведущим в уже мёртвый туннель, новый было не поднять, и человек шёл
/// переустанавливать службу.
///
/// Поэтому «файла нет» и «файл не прочитался» — разные вещи, и только
/// первое значит «выключено».
final class ConfigReadTests: XCTestCase {

    private var directory = ""

    override func setUp() {
        super.setUp()
        directory = NSTemporaryDirectory() + "/qpvpn-tests-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    private func путь(_ name: String) -> String { directory + "/" + name }

    func testФайлаНетЗначитЕщёНеНастраивали() {
        guard case .missing = ConfigStore.readConfig(at: путь("нет.json")) else {
            return XCTFail("Отсутствующий файл должен читаться как «не настраивали»")
        }
    }

    func testИспорченныйФайлНеСчитаетсяВыключеннымVpn() {
        let path = путь("битый.json")
        try? Data("{ это не json".utf8).write(to: URL(fileURLWithPath: path))

        switch ConfigStore.readConfig(at: path) {
        case .unreadable:
            break
        case .ok, .missing:
            XCTFail("Испорченный файл раньше выключал VPN и рвал связь")
        }
    }

    func testПустойФайлНеСчитаетсяВыключеннымVpn() {
        let path = путь("пустой.json")
        try? Data().write(to: URL(fileURLWithPath: path))

        switch ConfigStore.readConfig(at: path) {
        case .unreadable:
            break
        case .ok, .missing:
            XCTFail("Пустой файл раньше выключал VPN и рвал связь")
        }
    }

    func testЦелыеНастройкиЧитаютсяКакЕсть() throws {
        let path = путь("настройки.json")
        var config = TunnelConfig()
        config.enabled = true
        let data = try JSONEncoder().encode(config)
        try data.write(to: URL(fileURLWithPath: path))

        guard case .ok(let прочитано) = ConfigStore.readConfig(at: path) else {
            return XCTFail("Целый файл должен прочитаться")
        }
        XCTAssertTrue(прочитано.enabled)
    }

    func testВыключенныйVpnЧитаетсяКакВыключенный() throws {
        // Обратная сторона: когда человек действительно выключил VPN,
        // служба обязана это увидеть и опустить туннель.
        let path = путь("выключено.json")
        var config = TunnelConfig()
        config.enabled = false
        try JSONEncoder().encode(config).write(to: URL(fileURLWithPath: path))

        guard case .ok(let прочитано) = ConfigStore.readConfig(at: path) else {
            return XCTFail("Целый файл должен прочитаться")
        }
        XCTAssertFalse(прочитано.enabled)
    }

    func testКаталогСостоянияВосстанавливается() throws {
        // Каталог может пропасть — его сносят чистилки дисков и программа
        // удаления. Раньше запись после этого падала навсегда: в журнале
        // копились «не удалось записать статус».
        let пропавший = directory + "/пропал/состояние"
        try ConfigStore.writeAtomically(data: Data("{}".utf8),
                                        to: пропавший + "/status.json",
                                        permissions: 0o664)

        XCTAssertTrue(FileManager.default.fileExists(atPath: пропавший + "/status.json"))
    }
}
