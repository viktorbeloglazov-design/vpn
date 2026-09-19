import Foundation

/// Второй переключатель: рабочие ресурсы.
///
/// Адреса заложены в приложение. Включён — они идут через VPN, выключен —
/// напрямую. Списки те же, что в версиях для Android и Windows.
enum WorkFilter {

    struct Resource {
        let title: String
        let url: String

        /// Узел из ссылки: без схемы, пути и порта.
        var host: String {
            var text = url
            if let scheme = text.range(of: "://") {
                text = String(text[scheme.upperBound...])
            }
            if let slash = text.firstIndex(of: "/") {
                text = String(text[text.startIndex..<slash])
            }
            if let colon = text.firstIndex(of: ":") {
                text = String(text[text.startIndex..<colon])
            }
            return text
        }
    }

    static let resources: [Resource] = [
        Resource(title: "Ka", url: "https://135.106.142.73/Ka"),
        Resource(title: "Ka_old", url: "https://135.106.142.73/Ka_old"),
    ]

    /// Узлы без повторов — в таком виде они уходят в маршрутизацию.
    static var hosts: [String] {
        var seen = Set<String>()
        return resources.map(\.host).filter { seen.insert($0).inserted }
    }

    static var count: Int { resources.count }
}
