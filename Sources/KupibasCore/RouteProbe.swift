import Foundation

/// Проверка, каким путём система отправляет пакеты к конкретному сервису.
///
/// Разговоры «работает / не работает» упираются в один вопрос: идёт этот
/// сервис мимо VPN или через него. Система знает ответ точно — достаточно
/// спросить её про маршрут.
///
/// Раньше здесь лежали готовые адреса: считалось, что у крупных сервисов
/// они меняются годами. Оказалось, не годами: адреса Госуслуг и
/// Wildberries устарели, проверка спрашивала про чужие адреса и честно
/// отвечала «идёт через VPN». Человек видел «обход работает не полностью»
/// там, где всё работало. Теперь адрес спрашивается у DNS в тот же
/// момент — проверяется то же, чем пользуется сам человек.
public enum RouteProbe {

    /// Сервисы, которые обязаны идти мимо VPN.
    ///
    /// Картинки и файлы вынесены отдельной строкой не для красоты: у
    /// российских сервисов они лежат на других адресах, чем сам сайт.
    /// Отсюда и жалобы вида «сообщения ходят, а фото не грузятся» —
    /// сайт идёт напрямую, а его картинки уезжают в туннель.
    public static let landmarks: [(name: String, host: String)] = [
        ("МАХ", "max.ru"),
        ("МАХ, картинки", "i.max.ru"),
        ("МАХ, файлы", "st.max.ru"),
        ("Сбербанк", "online.sberbank.ru"),
        ("Госуслуги", "gosuslugi.ru"),
        ("Wildberries", "www.wildberries.ru"),
        ("Wildberries, картинки", "basket-01.wbbasket.ru"),
        ("Ozon", "ozon.ru"),
    ]

    public struct Result: Sendable {
        public let name: String
        public let host: String

        /// Адрес, который назвал DNS. Пусто — имя не разрешилось.
        public let address: String

        /// Через какой интерфейс: en0, utun5 и так далее.
        public let interface: String

        public init(name: String, host: String, address: String, interface: String) {
            self.name = name
            self.host = host
            self.address = address
            self.interface = interface
        }

        /// Удалось ли вообще выяснить путь.
        public var known: Bool { !address.isEmpty && !interface.isEmpty }

        /// Идёт мимо туннеля: имя интерфейса не похоже на туннельный.
        public var bypassesTunnel: Bool {
            known && !RouteGuard.isTunnel(interface: interface)
        }
    }

    /// Спрашивает систему про каждый сервис.
    public static func check(_ items: [(name: String, host: String)] = landmarks) -> [Result] {
        items.map { item in
            let address = resolve(item.host)
            return Result(name: item.name,
                          host: item.host,
                          address: address,
                          interface: address.isEmpty ? "" : interface(for: address))
        }
    }

    /// Первый адрес IPv4, который система выдаёт для имени.
    public static func resolve(_ host: String) -> String {
        var hints = addrinfo(ai_flags: 0,
                             ai_family: AF_INET,
                             ai_socktype: SOCK_STREAM,
                             ai_protocol: 0,
                             ai_addrlen: 0,
                             ai_canonname: nil,
                             ai_addr: nil,
                             ai_next: nil)
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return "" }
        defer { freeaddrinfo(list) }

        var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(first.pointee.ai_addr,
                          socklen_t(first.pointee.ai_addrlen),
                          &text, socklen_t(text.count),
                          nil, 0,
                          NI_NUMERICHOST) == 0
        else { return "" }

        return String(cString: text)
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
        let known = results.filter(\.known)
        guard !known.isEmpty else { return "Не удалось выяснить адреса — проверьте связь." }

        let direct = known.filter(\.bypassesTunnel)
        if direct.count == known.count { return "Российские сервисы идут напрямую — так и задумано." }

        // Называем поимённо: «часть сервисов» не говорит человеку ничего,
        // а «фото в МАХ идут через VPN» объясняет, почему они не грузятся.
        let inTunnel = known.filter { !$0.bypassesTunnel }.map(\.name).joined(separator: ", ")
        if direct.isEmpty { return "Всё проверенное идёт через VPN — обход не работает: \(inTunnel)." }
        return "Через VPN идёт то, что должно идти напрямую: \(inTunnel)."
    }
}
