import Foundation

/// Второй переключатель: рабочие ресурсы.
///
/// Адреса заложены в приложение. Включён — они идут через VPN, выключен —
/// напрямую. Списки те же, что в версиях для Android и Windows.
public enum WorkFilter {

    public struct Resource: Sendable {
        public let title: String
        public let url: String

        public init(title: String, url: String) {
            self.title = title
            self.url = url
        }

        /// Узел из ссылки: без схемы, пути и порта.
        public var host: String {
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

    public static let resources: [Resource] = [
        Resource(title: "Ka", url: "https://135.106.142.73/Ka"),
        Resource(title: "Ka_old", url: "https://135.106.142.73/Ka_old"),
    ]

    /// Узлы без повторов — в таком виде они уходят в маршрутизацию.
    public static var hosts: [String] {
        var seen = Set<String>()
        return resources.map(\.host).filter { seen.insert($0).inserted }
    }

    public static var count: Int { resources.count }
}
