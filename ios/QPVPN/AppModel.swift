import Foundation
import SwiftUI

/// Состояние экрана и всё, что с ним делают.
@MainActor
final class AppModel: ObservableObject {

    @Published var config: AppConfig {
        didSet {
            store.update { $0 = config }
            if oldValue != config { Task { await reapply() } }
        }
    }

    @Published var note = ""
    @Published var noteIsError = false
    @Published var ipText = ""
    @Published var ipIsKazakhstan = false
    @Published var checkingIp = false
    @Published var busy = false
    @Published var rxBytes: Int64 = 0
    @Published var txBytes: Int64 = 0

    let tunnel = TunnelManager()
    private let store = Store()
    private var profileText: String?

    init() {
        config = Store().config
        profileText = Self.savedProfileText()
    }

    var hasProfile: Bool { profileText != nil }

    var profileSummary: String {
        guard let text = profileText, let profile = try? WgProfile.parse(text) else {
            return "Ключа нет"
        }
        return "\(profile.protocolName) · \(profile.endpointHost)"
    }

    // MARK: - Ключ

    /// Общий путь для всего, чем делятся: ссылка, QR-код, файл настроек.
    func importPayload(_ payload: String, source: String) async {
        guard let text = SharedLink.extractConfig(payload) else {
            show(SharedLink.looksLikeLink(payload)
                 ? "\(source): это ссылка не с WireGuard — приложение понимает WireGuard и AmneziaWG."
                 : "\(source): настройки WireGuard не нашлись.", error: true)
            return
        }

        do {
            let profile = try WgProfile.parse(text)
            busy = true
            defer { busy = false }

            try await tunnel.save(profile: profile, config: config)
            Self.saveProfileText(text)
            profileText = text
            show("Ключ загружен из \(source): \(profile.protocolName), сервер \(profile.endpointHost).", error: false)
        } catch {
            show("\(source): \(error.localizedDescription)", error: true)
        }
    }

    func removeProfile() async {
        await tunnel.removeProfile()
        Self.saveProfileText(nil)
        profileText = nil
        show("Ключ удалён.", error: false)
    }

    /// Правки применяются сразу: маршруты пересчитываются и уезжают в профиль.
    func reapply() async {
        guard let text = profileText, let profile = try? WgProfile.parse(text) else { return }
        busy = true
        defer { busy = false }
        try? await tunnel.save(profile: profile, config: config)
    }

    func refreshTraffic() async {
        guard tunnel.state == .connected, let traffic = await tunnel.traffic() else { return }
        rxBytes = traffic.rx
        txBytes = traffic.tx
    }

    // MARK: - Проверка адреса

    func checkIp() async {
        checkingIp = true
        defer { checkingIp = false }

        guard let url = URL(string: "https://ipinfo.io/json") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let ip = json["ip"] as? String ?? ""
            let country = json["country"] as? String ?? ""
            let city = json["city"] as? String ?? ""

            ipIsKazakhstan = country == "KZ"
            ipText = "\(ip) · \(Self.countryName(country)) \(city)".trimmingCharacters(in: .whitespaces)
        } catch {
            ipText = "Проверить не вышло: \(error.localizedDescription)"
            ipIsKazakhstan = false
        }
    }

    // MARK: - Внутреннее

    private func show(_ text: String, error: Bool) {
        note = text
        noteIsError = error
    }

    private static func countryName(_ code: String) -> String {
        switch code {
        case "KZ": return "Казахстан"
        case "RU": return "Россия"
        case "NL": return "Нидерланды"
        case "DE": return "Германия"
        case "US": return "США"
        default: return code
        }
    }

    /// Ключ хранится в связке ключей: файлы приложения доступны при разборе
    /// резервной копии, а связка — нет.
    private static let keychainAccount = "qpvpn.profile"

    private static func saveProfileText(_ text: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "kz.qpvpn",
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)

        guard let text, let data = text.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func savedProfileText() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "kz.qpvpn",
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
