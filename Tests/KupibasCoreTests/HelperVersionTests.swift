import XCTest
@testable import KupibasCore

/// Служба должна обновляться вместе с приложением.
///
/// Приложение обновляют перетаскиванием в «Программы», а служба остаётся
/// прежней и продолжает работать по-старому. Получается худшее из
/// возможного: в приложении новая логика, а ошибку показывает старая
/// служба — та, которой в коде уже нет. Отметка о версии это ловит.
final class HelperVersionTests: XCTestCase {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // KupibasCoreTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // корень
    }

    func testVersionFileLivesNextToTheService() {
        XCTAssertTrue(Paths.helperVersionFile.hasPrefix(Paths.helperDir + "/"),
                      "отметка о версии должна лежать рядом со службой")
        XCTAssertTrue(Paths.helperVersionFile.hasSuffix("/version"))
    }

    func testInstallerWritesTheVersion() throws {
        // Без этой строки в установщике отметки не появится, и приложение
        // не узнает, что служба устарела.
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/install-helper.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(script.contains("CFBundleShortVersionString"),
                      "установщик должен брать версию из Info.plist приложения")
        XCTAssertTrue(script.contains("$HELPER_DIR/version"),
                      "установщик должен записывать отметку рядом со службой")
    }

    func testInstallerNoLongerNeedsWgQuick() throws {
        // wg-quick требует bash 4+, которого в macOS нет: если он снова
        // появится в установщике, туннель перестанет подниматься.
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/install-helper.sh"),
            encoding: .utf8
        )
        let mentions = script
            .split(separator: "\n")
            .filter { $0.contains("wg-quick") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        XCTAssertTrue(mentions.isEmpty, "установщик снова зовёт wg-quick: \(mentions)")
    }
}
