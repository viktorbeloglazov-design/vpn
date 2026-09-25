import XCTest
@testable import KupibasCore

/// Проверка «куда на самом деле идёт трафик».
///
/// Раньше в ней лежали готовые адреса — считалось, что у крупных сервисов
/// они меняются годами. Адреса Госуслуг и Wildberries устарели, проверка
/// спрашивала про чужие адреса и честно отвечала «идёт через VPN».
/// Человек видел «обход работает не полностью» там, где всё работало.
final class RouteProbeTests: XCTestCase {

    func testПроверяютсяИменаАНеЗашитыеАдреса() {
        for landmark in RouteProbe.landmarks {
            XCTAssertTrue(Validation.isDomain(landmark.host),
                          "«\(landmark.host)» — не имя. Зашитый адрес устареет молча")
        }
    }

    func testКартинкиПроверяютсяОтдельноОтСайта() {
        // У российских сервисов картинки лежат на других адресах, чем сам
        // сайт. Отсюда жалобы «сообщения ходят, а фото не грузятся»: сайт
        // идёт напрямую, а его картинки уезжают в туннель.
        let hosts = RouteProbe.landmarks.map(\.host)

        XCTAssertTrue(hosts.contains("max.ru"))
        XCTAssertTrue(hosts.contains("i.max.ru"), "Картинки МАХ должны проверяться отдельно")
        XCTAssertTrue(hosts.contains("basket-01.wbbasket.ru"), "Картинки Wildberries — тоже")
    }

    func testВсеОриентирыРазные() {
        let names = RouteProbe.landmarks.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "Имена показываются в списке — они должны быть разными")
    }

    private func результат(_ name: String, _ interface: String, address: String = "1.2.3.4")
        -> RouteProbe.Result {
        RouteProbe.Result(name: name, host: name, address: address, interface: interface)
    }

    func testВсёНапрямуюЭтоХорошаяНовость() {
        let текст = RouteProbe.summary([
            результат("МАХ", "en0"),
            результат("Сбербанк", "en0"),
        ])
        XCTAssertTrue(текст.contains("напрямую"))
    }

    func testСервисыВТуннелеНазываютсяПоимённо() {
        // «Часть сервисов» не говорит человеку ничего, а «МАХ, картинки»
        // объясняет, почему не грузятся фото.
        let текст = RouteProbe.summary([
            результат("МАХ", "en0"),
            результат("МАХ, картинки", "utun4"),
        ])
        XCTAssertTrue(текст.contains("МАХ, картинки"), "В сводке должно быть видно, что именно ушло в туннель")
    }

    func testНеотвечающийАдресНеСчитаетсяПоломкой() {
        // Имя не разрешилось — это не «обход не работает», это «не узнали».
        let результаты = [результат("МАХ", "", address: "")]

        XCTAssertFalse(результаты[0].known)
        XCTAssertFalse(результаты[0].bypassesTunnel)
        XCTAssertTrue(RouteProbe.summary(результаты).contains("Не удалось"))
    }

    func testТуннельныйИнтерфейсУзнаётся() {
        XCTAssertTrue(результат("сервис", "en0").bypassesTunnel)
        XCTAssertFalse(результат("сервис", "utun4").bypassesTunnel)
        XCTAssertFalse(результат("сервис", "ipsec0").bypassesTunnel)
    }
}
