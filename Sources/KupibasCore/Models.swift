import Foundation

/// Режим маршрутизации трафика.
public enum TunnelMode: String, Codable, CaseIterable, Sendable {
    /// Весь трафик идёт через VPN.
    case full
    /// Через VPN идёт только то, что перечислено в правилах.
    case include
    /// Через VPN идёт всё, кроме перечисленного в правилах.
    case exclude

    public var title: String {
        switch self {
        case .full: return "Весь трафик через VPN"
        case .include: return "Только правила через VPN"
        case .exclude: return "Всё через VPN, кроме правил"
        }
    }

    public var subtitle: String {
        switch self {
        case .full:
            return "Казахстанский IP для всех соединений."
        case .include:
            return "Обычный интернет остаётся прямым, через VPN идут только выбранные сайты и подсети."
        case .exclude:
            return "Казахстанский IP по умолчанию, а перечисленные сайты и подсети идут напрямую."
        }
    }
}

/// Тип правила маршрутизации.
public enum RuleKind: String, Codable, CaseIterable, Sendable {
    /// Домен: демон резолвит его в IP и держит маршруты в актуальном состоянии.
    case domain
    /// Подсеть или одиночный IP-адрес (10.0.0.0/8, 1.2.3.4).
    case cidr

    public var title: String {
        switch self {
        case .domain: return "Домен"
        case .cidr: return "IP / подсеть"
        }
    }
}

/// Одно правило маршрутизации.
public struct RoutingRule: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: RuleKind
    public var value: String
    public var enabled: Bool
    public var note: String

    public init(id: String = UUID().uuidString,
                kind: RuleKind,
                value: String,
                enabled: Bool = true,
                note: String = "") {
        self.id = id
        self.kind = kind
        self.value = value
        self.enabled = enabled
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.kind = (try? c.decode(RuleKind.self, forKey: .kind)) ?? .domain
        self.value = (try? c.decode(String.self, forKey: .value)) ?? ""
        self.enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        self.note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }
}

/// Параметры WireGuard-сервера (выходной узел в Казахстане).
public struct ServerConfig: Codable, Hashable, Sendable {
    public var name: String
    public var endpoint: String
    public var publicKey: String
    public var presharedKey: String
    public var privateKey: String
    /// Адреса интерфейса, например ["10.8.0.2/32"].
    public var addresses: [String]
    /// DNS-серверы туннеля.
    public var dns: [String]
    public var mtu: Int
    public var persistentKeepalive: Int

    public init(name: String = "KZ",
                endpoint: String = "",
                publicKey: String = "",
                presharedKey: String = "",
                privateKey: String = "",
                addresses: [String] = [],
                dns: [String] = [],
                mtu: Int = 1420,
                persistentKeepalive: Int = 25) {
        self.name = name
        self.endpoint = endpoint
        self.publicKey = publicKey
        self.presharedKey = presharedKey
        self.privateKey = privateKey
        self.addresses = addresses
        self.dns = dns
        self.mtu = mtu
        self.persistentKeepalive = persistentKeepalive
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "KZ"
        self.endpoint = (try? c.decode(String.self, forKey: .endpoint)) ?? ""
        self.publicKey = (try? c.decode(String.self, forKey: .publicKey)) ?? ""
        self.presharedKey = (try? c.decode(String.self, forKey: .presharedKey)) ?? ""
        self.privateKey = (try? c.decode(String.self, forKey: .privateKey)) ?? ""
        self.addresses = (try? c.decode([String].self, forKey: .addresses)) ?? []
        self.dns = (try? c.decode([String].self, forKey: .dns)) ?? []
        self.mtu = (try? c.decode(Int.self, forKey: .mtu)) ?? 1420
        self.persistentKeepalive = (try? c.decode(Int.self, forKey: .persistentKeepalive)) ?? 25
    }

    /// Хост endpoint'а без порта (нужен для обходного маршрута).
    public var endpointHost: String {
        Validation.splitEndpoint(endpoint)?.host ?? ""
    }

    public var hasIPv6Address: Bool {
        addresses.contains { $0.contains(":") }
    }

    /// Причина, по которой конфигурация не готова к запуску, либо nil.
    public var validationError: String? {
        if privateKey.isEmpty { return "Не задан приватный ключ клиента." }
        if !Validation.isWireGuardKey(privateKey) { return "Приватный ключ клиента имеет неверный формат." }
        if publicKey.isEmpty { return "Не задан публичный ключ сервера." }
        if !Validation.isWireGuardKey(publicKey) { return "Публичный ключ сервера имеет неверный формат." }
        if !presharedKey.isEmpty && !Validation.isWireGuardKey(presharedKey) {
            return "Preshared-ключ имеет неверный формат."
        }
        if Validation.splitEndpoint(endpoint) == nil { return "Endpoint должен быть в виде host:port." }
        if addresses.isEmpty { return "Не задан адрес интерфейса (Address)." }
        for address in addresses where !Validation.isCIDR(address) {
            return "Адрес интерфейса «\(address)» некорректен."
        }
        for server in dns where !Validation.isIPAddress(server) {
            return "DNS-сервер «\(server)» некорректен."
        }
        if mtu < 1200 || mtu > 1500 { return "MTU должен быть в диапазоне 1200…1500." }
        return nil
    }
}

/// Дополнительные настройки поведения туннеля.
public struct TunnelOptions: Codable, Hashable, Sendable {
    /// Использовать DNS-серверы туннеля (в режиме include выключено по умолчанию).
    public var useTunnelDNS: Bool
    /// Отключать IPv6 на активных сетевых службах, пока VPN включён (защита от утечки реального адреса).
    public var disableIPv6: Bool
    /// Как часто перепроверять IP-адреса доменов из правил, минут.
    public var reresolveMinutes: Int
    /// Перезапускать туннель, если давно не было handshake.
    public var autoReconnect: Bool

    public init(useTunnelDNS: Bool = true,
                disableIPv6: Bool = true,
                reresolveMinutes: Int = 5,
                autoReconnect: Bool = true) {
        self.useTunnelDNS = useTunnelDNS
        self.disableIPv6 = disableIPv6
        self.reresolveMinutes = reresolveMinutes
        self.autoReconnect = autoReconnect
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.useTunnelDNS = (try? c.decode(Bool.self, forKey: .useTunnelDNS)) ?? true
        self.disableIPv6 = (try? c.decode(Bool.self, forKey: .disableIPv6)) ?? true
        self.reresolveMinutes = (try? c.decode(Int.self, forKey: .reresolveMinutes)) ?? 5
        self.autoReconnect = (try? c.decode(Bool.self, forKey: .autoReconnect)) ?? true
    }
}

/// Полная конфигурация, которую GUI пишет, а демон исполняет.
public struct TunnelConfig: Codable, Hashable, Sendable {
    public var version: Int
    /// Желаемое состояние: true — туннель должен быть поднят.
    public var enabled: Bool
    public var mode: TunnelMode
    public var server: ServerConfig
    public var rules: [RoutingRule]
    public var options: TunnelOptions

    public init(version: Int = 1,
                enabled: Bool = false,
                mode: TunnelMode = .full,
                server: ServerConfig = ServerConfig(),
                rules: [RoutingRule] = [],
                options: TunnelOptions = TunnelOptions()) {
        self.version = version
        self.enabled = enabled
        self.mode = mode
        self.server = server
        self.rules = rules
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        self.enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        self.mode = (try? c.decode(TunnelMode.self, forKey: .mode)) ?? .full
        self.server = (try? c.decode(ServerConfig.self, forKey: .server)) ?? ServerConfig()
        self.rules = (try? c.decode([RoutingRule].self, forKey: .rules)) ?? []
        self.options = (try? c.decode(TunnelOptions.self, forKey: .options)) ?? TunnelOptions()
    }

    public var activeRules: [RoutingRule] {
        rules.filter { $0.enabled && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Всё, что требует полного пересоздания туннеля при изменении.
    public var restartSignature: String {
        var parts: [String] = [String(version), mode.rawValue]
        parts.append(server.endpoint)
        parts.append(server.publicKey)
        parts.append(server.presharedKey)
        parts.append(server.privateKey)
        parts.append(server.addresses.joined(separator: ","))
        parts.append(server.dns.joined(separator: ","))
        parts.append(String(server.mtu))
        parts.append(String(server.persistentKeepalive))
        parts.append(options.useTunnelDNS ? "dns1" : "dns0")
        parts.append(options.disableIPv6 ? "v6off" : "v6on")
        return parts.joined(separator: "|")
    }

    /// Изменения здесь можно применить без перезапуска туннеля — только правкой маршрутов.
    public var rulesSignature: String {
        activeRules
            .map { "\($0.kind.rawValue):\($0.value.lowercased())" }
            .sorted()
            .joined(separator: ",")
    }
}

/// Состояние туннеля, которое демон публикует для GUI.
public enum TunnelState: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case error

    public var title: String {
        switch self {
        case .disconnected: return "Выключен"
        case .connecting: return "Подключение…"
        case .connected: return "Подключён"
        case .error: return "Ошибка"
        }
    }
}

public struct TunnelStatus: Codable, Hashable, Sendable {
    public var state: TunnelState
    public var mode: TunnelMode
    public var interfaceName: String
    public var serverName: String
    public var endpoint: String
    /// Момент установления соединения (unix time).
    public var connectedSince: Double
    /// Время последнего handshake (unix time), 0 — не было.
    public var lastHandshake: Double
    public var rxBytes: Int
    public var txBytes: Int
    /// Сколько маршрутов сейчас обслуживает демон.
    public var routeCount: Int
    public var message: String
    /// Момент последнего обновления файла — по нему GUI понимает, жив ли демон.
    public var updatedAt: Double

    public init(state: TunnelState = .disconnected,
                mode: TunnelMode = .full,
                interfaceName: String = "",
                serverName: String = "",
                endpoint: String = "",
                connectedSince: Double = 0,
                lastHandshake: Double = 0,
                rxBytes: Int = 0,
                txBytes: Int = 0,
                routeCount: Int = 0,
                message: String = "",
                updatedAt: Double = 0) {
        self.state = state
        self.mode = mode
        self.interfaceName = interfaceName
        self.serverName = serverName
        self.endpoint = endpoint
        self.connectedSince = connectedSince
        self.lastHandshake = lastHandshake
        self.rxBytes = rxBytes
        self.txBytes = txBytes
        self.routeCount = routeCount
        self.message = message
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.state = (try? c.decode(TunnelState.self, forKey: .state)) ?? .disconnected
        self.mode = (try? c.decode(TunnelMode.self, forKey: .mode)) ?? .full
        self.interfaceName = (try? c.decode(String.self, forKey: .interfaceName)) ?? ""
        self.serverName = (try? c.decode(String.self, forKey: .serverName)) ?? ""
        self.endpoint = (try? c.decode(String.self, forKey: .endpoint)) ?? ""
        self.connectedSince = (try? c.decode(Double.self, forKey: .connectedSince)) ?? 0
        self.lastHandshake = (try? c.decode(Double.self, forKey: .lastHandshake)) ?? 0
        self.rxBytes = (try? c.decode(Int.self, forKey: .rxBytes)) ?? 0
        self.txBytes = (try? c.decode(Int.self, forKey: .txBytes)) ?? 0
        self.routeCount = (try? c.decode(Int.self, forKey: .routeCount)) ?? 0
        self.message = (try? c.decode(String.self, forKey: .message)) ?? ""
        self.updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
    }

    /// Демон считается живым, если писал статус в последние 15 секунд.
    public var isDaemonAlive: Bool {
        Date().timeIntervalSince1970 - updatedAt < 15
    }
}
