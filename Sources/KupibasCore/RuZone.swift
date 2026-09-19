import Foundation

/// Адресное пространство России, вшитое в приложение.
///
/// Нужно для главного фильтра: через VPN идёт всё, кроме этих подсетей.
/// Так заблокированный сервис открывается, даже если его адрес программе
/// незнаком, а банки и госуслуги работают напрямую.
public enum RuZone {

    /// Куда установщик кладёт список — оттуда его читает служба.
    public static let installedPath = "/Library/Application Support/QPVPN/ru_ipv4.txt"

    private static var cache: [Ipv4Net]?

    /// Читает список: сначала рядом со службой, затем из переданных путей.
    public static func networks(extraPaths: [String] = []) -> [Ipv4Net] {
        if let cache { return cache }

        for path in [installedPath] + extraPaths {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let nets = parse(text)
            if !nets.isEmpty {
                cache = nets
                return nets
            }
        }

        cache = []
        return []
    }

    public static func parse(_ text: String) -> [Ipv4Net] {
        var nets: [Ipv4Net] = []
        nets.reserveCapacity(9000)
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let net = Cidr.parse(trimmed) else { return }
            nets.append(net)
        }
        return nets
    }

    public static func reload() {
        cache = nil
    }

    public static var count: Int { networks().count }
}
