import Foundation

/// Что уходит в туннель.
enum TunnelMode: String, Codable, CaseIterable {
    /// Весь трафик через VPN.
    case full

    /// Через VPN идут только адреса из правил.
    case include

    /// Через VPN идёт всё, кроме адресов из правил.
    case exclude

    var title: String {
        switch self {
        case .full: return "Весь трафик через VPN"
        case .include: return "Только правила через VPN"
        case .exclude: return "Всё через VPN, кроме правил"
        }
    }

    var subtitle: String {
        switch self {
        case .full: return "Казахстанский адрес для всех соединений."
        case .include: return "Обычный интернет остаётся прямым, в туннель уходят только выбранные сайты."
        case .exclude: return "Казахстанский адрес по умолчанию, перечисленные сайты идут напрямую."
        }
    }
}

enum RuleKind: String, Codable {
    case domain
    case cidr
}

struct RoutingRule: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var kind: RuleKind = .domain
    var value: String = ""
    var enabled: Bool = true
    var note: String = ""
}

struct AppConfig: Codable, Equatable {
    var version = 1

    /// Главный фильтр: через VPN идёт только то, что не работает из России.
    var mainFilter = true

    /// Рабочие ресурсы: заложенные адреса идут через VPN.
    var workFilter = true

    var mode: TunnelMode = .full
    var rules: [RoutingRule] = []

    /// Использовать DNS-серверы из профиля.
    var useTunnelDns = true

    /// Вся российская зона идёт мимо туннеля.
    var bypassRuZone = true

    var activeRules: [RoutingRule] {
        rules.filter { $0.enabled && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Режим, который действительно применяется с учётом главного фильтра.
    var effectiveMode: TunnelMode { mainFilter ? .include : mode }
}

/// Настройки на диске. Ключ здесь не хранится: он уезжает в системное
/// хранилище VPN-профилей вместе с самим профилем.
final class Store {

    private let defaults = UserDefaults.standard
    private let key = "qpvpn.config"

    private(set) var config: AppConfig {
        didSet { save() }
    }

    init() {
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = stored
        } else {
            config = AppConfig()
        }
    }

    func update(_ transform: (inout AppConfig) -> Void) {
        var copy = config
        transform(&copy)
        config = copy
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }
}
