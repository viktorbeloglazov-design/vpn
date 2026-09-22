import Foundation

/// Проверка, каким путём система отправляет пакеты к конкретному адресу.
///
/// Разговоры «работает / не работает» упираются в один вопрос: идёт этот
/// сервис мимо VPN или через него. Система знает ответ точно — достаточно
/// спросить её про маршрут.
public enum RouteProbe {

    /// Известные адреса сервисов, которые обязаны идти мимо VPN.
    ///
    /// Они не для маршрутизации — только чтобы спросить систему, куда
    /// сейчас ведёт путь. Адреса стабильные, у крупных сервисов они
    /// меняются годами.
    public static let landmarks: [(name: String, address: String)] = [
        ("МАХ", "155.212.204.5"),
        ("Сбербанк", "194.54.14.140"),
        ("Госуслуги", "212.42.65.4"),
        ("Wildberries", "178.253.20.10"),
    ]

    public struct Result: Sendable {
        public let name: String
        public let address: String
        /// Через какой интерфейс: en0, utun5 и так далее.
        public let interface: String

        /// Идёт мимо туннеля: имя интерфейса не похоже на туннельный.
        public var bypassesTunnel: Bool {
            !interface.isEmpty && !interface.hasPrefix("utun") && !interface.hasPrefix("ipsec")
        }
    }

    /// Спрашивает систему про каждый адрес.
    public static func check(_ items: [(name: String, address: String)] = landmarks) -> [Result] {
        items.map { Result(name: $0.name, address: $0.address, interface: interface(for: $0.address)) }
    }

    /// Интерфейс, через который система отправит пакет к адресу.
    public static func interface(for address: String) -> String {
        let output = run("/sbin/route", ["-n", "get", address])
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("interface:") else { continue }
            return trimmed
                .replacingOccurrences(of: "interface:", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    /// Спрашивает систему и возвращает её ответ.
    ///
    /// Своим запуском, а не общей оболочкой: её код живёт в службе,
    /// а спрашивать про маршруты нужно и приложению — прав для этого
    /// не требуется.
    private static func run(_ tool: String, _ arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        guard (try? task.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Короткая сводка для окна и отчёта диагностики.
    public static func summary(_ results: [Result]) -> String {
        guard !results.isEmpty else { return "" }
        let direct = results.filter(\.bypassesTunnel).count
        if direct == results.count { return "Российские сервисы идут напрямую — так и задумано." }
        if direct == 0 { return "Все проверенные российские сервисы идут через VPN — обход не работает." }
        return "Часть российских сервисов идёт через VPN: обход работает не полностью."
    }
}
