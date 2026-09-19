import Foundation

/// Проверка и нормализация пользовательского ввода: ключи, адреса, домены.
public enum Validation {

    public static func isIPv4(_ value: String) -> Bool {
        var addr = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &addr) == 1 }
    }

    public static func isIPv6(_ value: String) -> Bool {
        var addr = in6_addr()
        return value.withCString { inet_pton(AF_INET6, $0, &addr) == 1 }
    }

    public static func isIPAddress(_ value: String) -> Bool {
        isIPv4(value) || isIPv6(value)
    }

    /// Принимает "1.2.3.4/24", "2001:db8::/32" и одиночные адреса.
    public static func isCIDR(_ value: String) -> Bool {
        let parts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let host = String(parts[0])
        guard isIPAddress(host) else { return false }
        if parts.count == 1 { return true }
        guard let prefix = Int(parts[1]) else { return false }
        let maxPrefix = isIPv6(host) ? 128 : 32
        return prefix >= 0 && prefix <= maxPrefix
    }

    /// Приводит одиночный адрес к виду /32 или /128.
    public static func normalizeCIDR(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard isCIDR(trimmed) else { return nil }
        if trimmed.contains("/") { return trimmed }
        return trimmed + (isIPv6(trimmed) ? "/128" : "/32")
    }

    public static func isDomain(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 253, trimmed.contains(".") else { return false }
        guard !trimmed.hasPrefix("."), !trimmed.hasSuffix("."), !trimmed.contains("..") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return trimmed.split(separator: ".").allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
        }
    }

    /// Ключ WireGuard — 32 байта в base64 (44 символа).
    public static func isWireGuardKey(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 44, trimmed.hasSuffix("=") else { return false }
        guard let data = Data(base64Encoded: trimmed) else { return false }
        return data.count == 32
    }

    /// Разбирает "host:port" и "[2001:db8::1]:51820".
    public static func splitEndpoint(_ value: String) -> (host: String, port: Int)? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var host = ""
        var portPart = ""
        if trimmed.hasPrefix("[") {
            guard let close = trimmed.firstIndex(of: "]") else { return nil }
            host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            let rest = trimmed[trimmed.index(after: close)...]
            guard rest.hasPrefix(":") else { return nil }
            portPart = String(rest.dropFirst())
        } else {
            guard let colon = trimmed.lastIndex(of: ":") else { return nil }
            host = String(trimmed[trimmed.startIndex..<colon])
            portPart = String(trimmed[trimmed.index(after: colon)...])
        }
        guard let port = Int(portPart), port > 0, port <= 65535 else { return nil }
        guard isIPAddress(host) || isDomain(host) else { return nil }
        return (host, port)
    }

    /// Ошибка для правила маршрутизации, либо nil.
    public static func ruleError(kind: RuleKind, value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Пустое значение." }
        switch kind {
        case .domain:
            return isDomain(trimmed) ? nil : "«\(trimmed)» не похоже на домен (пример: kaspi.kz)."
        case .cidr:
            return isCIDR(trimmed) ? nil : "«\(trimmed)» не похоже на IP или подсеть (пример: 92.46.0.0/16)."
        }
    }
}
