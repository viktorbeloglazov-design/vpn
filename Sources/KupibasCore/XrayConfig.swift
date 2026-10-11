import Foundation

/// Настройки для xray, собранные из ключа.
///
/// Устройство одно на Mac и на Android: xray слушает на этом же
/// компьютере обычный socks-вход, а туннельный интерфейс (utun на Mac,
/// VpnService на Android) передаёт ему всё, что система решила вести
/// через VPN. Какие адреса туда попадают — решает не xray, а прежняя
/// маршрутизация: список сервисов, Gmail мимо и так далее. Поэтому
/// правил маршрутизации внутри xray нет: всё, что пришло, уходит на
/// сервер.
public enum XrayConfig {

    /// Порт socks-входа. Слушает только сам компьютер.
    public static let socksPort = 10808

    public static func render(_ link: XrayLink, socksPort: Int = socksPort, logLevel: String = "warning") -> String {
        let config: [String: Any] = [
            "log": ["loglevel": logLevel],
            "inbounds": [[
                "tag": "socks",
                "listen": "127.0.0.1",
                "port": socksPort,
                "protocol": "socks",
                "settings": ["auth": "noauth", "udp": true, "ip": "127.0.0.1"],
            ]],
            "outbounds": [
                outbound(link),
                ["tag": "direct", "protocol": "freedom"],
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: config,
                                                 options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Выход на сервер.
    public static func outbound(_ link: XrayLink) -> [String: Any] {
        var result: [String: Any] = ["tag": "proxy"]
        switch link.kind {
        case .vless:
            var user: [String: Any] = ["id": link.secret,
                                       "encryption": link.method.isEmpty ? "none" : link.method]
            if !link.flow.isEmpty { user["flow"] = link.flow }
            result["protocol"] = "vless"
            result["settings"] = ["vnext": [["address": link.host, "port": link.port, "users": [user]]]]
        case .vmess:
            result["protocol"] = "vmess"
            result["settings"] = ["vnext": [["address": link.host, "port": link.port,
                                             "users": [["id": link.secret,
                                                        "security": link.method.isEmpty ? "auto" : link.method]]]]]
        case .trojan:
            result["protocol"] = "trojan"
            result["settings"] = ["servers": [["address": link.host, "port": link.port, "password": link.secret]]]
        case .shadowsocks:
            result["protocol"] = "shadowsocks"
            result["settings"] = ["servers": [["address": link.host, "port": link.port,
                                               "method": link.method, "password": link.secret]]]
        }
        if link.kind != .shadowsocks {
            result["streamSettings"] = stream(link)
        }
        return result
    }

    static func stream(_ link: XrayLink) -> [String: Any] {
        var stream: [String: Any] = ["network": link.network, "security": link.security]

        switch link.security {
        case "reality":
            var reality: [String: Any] = [
                "serverName": link.sni,
                "fingerprint": link.fingerprint.isEmpty ? "chrome" : link.fingerprint,
                "publicKey": link.publicKey,
            ]
            if !link.shortId.isEmpty { reality["shortId"] = link.shortId }
            if !link.spiderX.isEmpty { reality["spiderX"] = link.spiderX }
            stream["realitySettings"] = reality
        case "tls":
            var tls: [String: Any] = ["allowInsecure": link.allowInsecure]
            let name = link.sni.isEmpty ? link.hostHeader : link.sni
            if !name.isEmpty { tls["serverName"] = name }
            if !link.fingerprint.isEmpty { tls["fingerprint"] = link.fingerprint }
            if !link.alpn.isEmpty { tls["alpn"] = link.alpn }
            stream["tlsSettings"] = tls
        default:
            break
        }

        switch link.network {
        case "ws":
            var ws: [String: Any] = ["path": link.path.isEmpty ? "/" : link.path]
            if !link.hostHeader.isEmpty { ws["host"] = link.hostHeader }
            stream["wsSettings"] = ws
        case "grpc":
            stream["grpcSettings"] = ["serviceName": link.serviceName,
                                      "multiMode": link.mode == "multi"]
        case "xhttp":
            var xhttp: [String: Any] = ["path": link.path.isEmpty ? "/" : link.path]
            if !link.hostHeader.isEmpty { xhttp["host"] = link.hostHeader }
            if !link.mode.isEmpty { xhttp["mode"] = link.mode }
            stream["xhttpSettings"] = xhttp
        case "httpupgrade":
            var upgrade: [String: Any] = ["path": link.path.isEmpty ? "/" : link.path]
            if !link.hostHeader.isEmpty { upgrade["host"] = link.hostHeader }
            stream["httpupgradeSettings"] = upgrade
        case "tcp" where link.headerType == "http":
            var request: [String: Any] = ["path": [link.path.isEmpty ? "/" : link.path]]
            if !link.hostHeader.isEmpty { request["headers"] = ["Host": [link.hostHeader]] }
            stream["tcpSettings"] = ["header": ["type": "http", "request": request]]
        default:
            break
        }
        return stream
    }
}
