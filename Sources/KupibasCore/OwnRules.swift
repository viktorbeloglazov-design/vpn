import Foundation

/// Свои сайты и адреса, которые человек добавляет через VPN сам.
///
/// Зашитый список закрывает обычные нужды, но не все: кому-то нужен свой
/// сайт, редкий сервис, рабочий адрес за границей. Поле для этого — одно,
/// и правила в нём пишутся как на бумаге: по одному в строке.
///
/// Разбор нарочно терпимый. Человек впишет и `example.com`, и
/// `https://example.com/page`, и `www.example.com`, и адрес сети — всё
/// это должно сработать, а не вызвать ругань про формат.
public enum OwnRules {

    /// Разбирает то, что человек вписал в поле.
    public static func parse(_ text: String) -> [RoutingRule] {
        var result: [RoutingRule] = []
        var seen: Set<String> = []

        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "," }) {
            guard let rule = rule(from: String(line)) else { continue }
            let key = "\(rule.kind.rawValue):\(rule.value)"
            guard seen.insert(key).inserted else { continue }
            result.append(rule)
        }
        return result
    }

    /// Строки, которые человек вписал, но понять их не вышло.
    ///
    /// Нужны, чтобы сказать об этом в окне: молча проглотить опечатку
    /// хуже, чем сказать «эту строку не понял».
    public static func unreadable(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && rule(from: $0) == nil }
    }

    /// Обратно в текст для поля — чтобы человек видел то, что сохранилось.
    public static func text(from rules: [RoutingRule]) -> String {
        rules.map(\.value).joined(separator: "\n")
    }

    // MARK: - Внутреннее

    private static func rule(from line: String) -> RoutingRule? {
        var value = line.trimmingCharacters(in: .whitespaces).lowercased()
        guard !value.isEmpty, !value.hasPrefix("#") else { return nil }

        // Человек нередко вставляет ссылку целиком — берём из неё имя.
        for prefix in ["https://", "http://"] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        if let slash = value.firstIndex(of: "/") {
            // Путь после имени нам не нужен, а «/24» в адресе сети — нужен.
            let tail = value[value.index(after: slash)...]
            if tail.isEmpty || !tail.allSatisfy(\.isNumber) {
                value = String(value[value.startIndex..<slash])
            }
        }
        // Порт и пользователя тоже отбрасываем: маршрут прокладывается
        // до узла, а не до порта.
        if let at = value.lastIndex(of: "@") {
            value = String(value[value.index(after: at)...])
        }
        if let colon = value.firstIndex(of: ":"), !value.contains("::") {
            value = String(value[value.startIndex..<colon])
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !value.isEmpty else { return nil }

        if let cidr = Validation.normalizeCIDR(value) {
            return RoutingRule(kind: .cidr, value: cidr, note: "своё")
        }
        if Validation.isDomain(value) {
            return RoutingRule(kind: .domain, value: value, note: "своё")
        }
        return nil
    }
}
