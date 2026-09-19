import Foundation
import NetworkExtension

/// Управление системным VPN-профилем.
///
/// На iPhone туннель живёт в отдельном расширении, а приложение только
/// сохраняет профиль в системные настройки и просит его включить.
/// Настройки туннеля передаются расширению вместе с профилем.
@MainActor
final class TunnelManager: ObservableObject {

    enum State: Equatable {
        case notReady
        case disconnected
        case connecting
        case connected
        case failed(String)

        var title: String {
            switch self {
            case .notReady: return "Нет ключа"
            case .disconnected: return "Выключен"
            case .connecting: return "Подключение…"
            case .connected: return "Подключён"
            case .failed: return "Ошибка"
            }
        }
    }

    @Published private(set) var state: State = .notReady
    @Published private(set) var serverName = ""
    @Published private(set) var routeCount = 0
    @Published private(set) var protocolName = ""
    @Published private(set) var note = ""

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    init() {
        Task { await load() }
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.readStatus() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Профиль

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first
            if let saved = manager?.protocolConfiguration as? NETunnelProviderProtocol {
                serverName = saved.serverAddress ?? ""
                protocolName = saved.providerConfiguration?["protocolName"] as? String ?? ""
                routeCount = saved.providerConfiguration?["routeCount"] as? Int ?? 0
            }
            readStatus()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var hasProfile: Bool { manager != nil }

    /// Сохраняет ключ и посчитанные маршруты в системный профиль.
    func save(profile: WgProfile, config: AppConfig) async throws {
        let routes = await RouteBuilder.routes(for: config, profile: profile)
        let text = profile.configText(
            allowedIps: routes,
            includeDns: config.useTunnelDns && config.effectiveMode != .include
        )

        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let target = managers.first ?? NETunnelProviderManager()

        let settings = NETunnelProviderProtocol()
        settings.providerBundleIdentifier = Self.tunnelBundleId
        settings.serverAddress = profile.endpointHost
        settings.providerConfiguration = [
            "wgQuickConfig": text,
            "protocolName": profile.protocolName,
            "routeCount": routes.count,
        ]

        target.protocolConfiguration = settings
        target.localizedDescription = "QP VPN"
        target.isEnabled = true

        try await target.saveToPreferences()
        // Перечитываем: система возвращает профиль с заполненными полями.
        try await target.loadFromPreferences()

        manager = target
        serverName = profile.endpointHost
        protocolName = profile.protocolName
        routeCount = routes.count
        readStatus()
    }

    func removeProfile() async {
        guard let manager else { return }
        try? await manager.removeFromPreferences()
        self.manager = nil
        serverName = ""
        protocolName = ""
        routeCount = 0
        state = .notReady
    }

    // MARK: - Включение

    func start() {
        guard let manager else {
            state = .notReady
            return
        }
        do {
            try manager.connection.startVPNTunnel()
            state = .connecting
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    func toggle() {
        if state == .connected || state == .connecting { stop() } else { start() }
    }

    /// Счётчики трафика спрашиваем у самого расширения.
    func traffic() async -> (rx: Int64, tx: Int64)? {
        guard let session = manager?.connection as? NETunnelProviderSession else { return nil }
        guard let message = "traffic".data(using: .utf8) else { return nil }

        return await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(message) { response in
                    guard let response,
                          let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
                    else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let rx = (json["rx"] as? NSNumber)?.int64Value ?? 0
                    let tx = (json["tx"] as? NSNumber)?.int64Value ?? 0
                    continuation.resume(returning: (rx, tx))
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func readStatus() {
        guard let manager else {
            state = .notReady
            return
        }
        switch manager.connection.status {
        case .connected: state = .connected
        case .connecting, .reasserting: state = .connecting
        case .disconnecting, .disconnected, .invalid: state = .disconnected
        @unknown default: state = .disconnected
        }
    }

    private static var tunnelBundleId: String {
        (Bundle.main.bundleIdentifier ?? "kz.qpvpn") + ".tunnel"
    }
}
