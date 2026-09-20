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

    /// Главный фильтр: через VPN идёт всё, кроме российских адресов.
    ///
    /// Заблокированный сервис открывается, даже если его адрес программе
    /// незнаком: снаружи туннеля остаётся только российская зона.
    var mainFilter = true

    /// Рабочие ресурсы: заложенные адреса идут через VPN.
    ///
    /// Единственное, что человек выбирает сам, — всё остальное зашито.
    var workFilter = true

    var mode: TunnelMode = .exclude
    var rules: [RoutingRule] = []

    /// Использовать DNS-серверы из профиля.
    var useTunnelDns = true

    /// Вся российская зона идёт мимо туннеля.
    var bypassRuZone = true

    var activeRules: [RoutingRule] {
        rules.filter { $0.enabled && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Режим, который действительно применяется.
    var effectiveMode: TunnelMode { .exclude }

    /// Настройки, приведённые к зашитому поведению.
    ///
    /// Маршрутизация не настраивается: заблокированные сервисы всегда идут
    /// через VPN, российские адреса — всегда напрямую. Человек выбирает
    /// только рабочие ресурсы, поэтому `workFilter` здесь не трогается.
    func pinned() -> AppConfig {
        var copy = self
        copy.mainFilter = true
        copy.mode = .exclude
        copy.rules = []
        copy.useTunnelDns = true
        copy.bypassRuZone = true
        return copy
    }
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
        // Что бы ни лежало в памяти от прошлых версий, в работу уходит
        // одно и то же поведение: настраивать маршруты больше негде.
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = stored.pinned()
        } else {
            config = AppConfig()
        }
    }

    func update(_ transform: (inout AppConfig) -> Void) {
        var copy = config
        transform(&copy)
        config = copy.pinned()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }
}
