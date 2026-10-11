import Foundation

/// Ключ, как его вставил человек, — в настройки сервера.
///
/// Одно место для всех способов: вставка текста, файл, QR-код. Сначала
/// ищем ключ X-Ray (на нём теперь работает сервер), потом прежние:
/// ссылку vpn:// и файл WireGuard или AmneziaWG.
public enum KeyImport {

    public static func parse(_ text: String, name: String = "KZ") throws -> ServerConfig {
        if XrayLink.looksLikeLink(text) {
            let link = try XrayLink.parse(text)
            return ServerConfig(xray: link, raw: XrayLink.find(in: text) ?? text, name: name)
        }
        return try WireGuardConfig.parse(SharedLink.extractConfig(text) ?? text, name: name)
    }

    /// Похоже ли это на ключ хоть какого вида — для QR-кодов.
    public static func looksLikeKey(_ text: String) -> Bool {
        XrayLink.looksLikeLink(text) || SharedLink.looksLikeLink(text)
            || text.contains("[Interface]")
    }
}
