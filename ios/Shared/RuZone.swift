import Foundation

/// Адресное пространство России, вшитое в приложение.
///
/// Нужно для режима «всё через VPN, кроме российской зоны»: из туннеля
/// вычитаются все выданные России подсети, и российские сайты открываются
/// с домашнего адреса без единого правила.
enum RuZone {

    private static var cache: [Ipv4Net]?

    static func networks(bundle: Bundle = .main) -> [Ipv4Net] {
        if let cache { return cache }

        guard let url = bundle.url(forResource: "ru_ipv4", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            cache = []
            return []
        }

        var nets: [Ipv4Net] = []
        nets.reserveCapacity(9000)
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let net = Cidr.parse(trimmed) else { return }
            nets.append(net)
        }

        cache = nets
        return nets
    }

    static func count(bundle: Bundle = .main) -> Int { networks(bundle: bundle).count }
}
