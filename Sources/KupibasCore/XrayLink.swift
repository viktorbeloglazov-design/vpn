import Foundation

/// Ключ X-Ray: ссылка vless://, vmess://, trojan:// или ss://.
///
/// Сервер теперь работает на X-Ray. Ключ к нему — одна строка-ссылка:
/// в ней адрес сервера, идентификатор и то, как соединение маскируется
/// (Reality, TLS, вебсокет). Из неё служба собирает настройки для xray.
///
/// Разбор терпимый, как и у прежних ключей: лишние пробелы, перевод
/// строки, ссылка внутри текста письма — всё это человек вставит,
/// и всё это должно работать.
public struct XrayLink: Hashable, Sendable {

    public enum Kind: String, Sendable {
        case vless, vmess, trojan, shadowsocks
    }

    public enum ParseError: LocalizedError, Equatable {
        case notALink
        case unsupported(String)
        case missing(String)

        public var errorDescription: String? {
            switch self {
            case .notALink:
                return "Это не ключ X-Ray: ожидается ссылка vless://, vmess://, trojan:// или ss://."
            case .unsupported(let what):
                return "Ключ X-Ray с «\(what)» приложение не понимает."
            case .missing(let what):
                return "В ключе X-Ray нет \(what)."
            }
        }
    }

    public var kind: Kind
    public var host: String
    public var port: Int
    /// UUID для VLESS и VMess, пароль для Trojan и Shadowsocks.
    public var secret: String
    /// Метод шифрования Shadowsocks или VMess.
    public var method: String
    /// xtls-rprx-vision и подобное — только для VLESS.
    public var flow: String
    /// tcp, ws, grpc, xhttp, httpupgrade, kcp.
    public var network: String
    /// none, tls, reality.
    public var security: String
    public var sni: String
    public var fingerprint: String
    public var alpn: [String]
    public var publicKey: String
    public var shortId: String
    public var spiderX: String
    public var path: String
    public var hostHeader: String
    public var serviceName: String
    public var mode: String
    public var headerType: String
    public var allowInsecure: Bool
    /// Имя из ссылки (после #) — для показа в окне.
    public var name: String

    public init(kind: Kind, host: String, port: Int, secret: String,
                method: String = "", flow: String = "", network: String = "tcp",
                security: String = "none", sni: String = "", fingerprint: String = "",
                alpn: [String] = [], publicKey: String = "", shortId: String = "",
                spiderX: String = "", path: String = "", hostHeader: String = "",
                serviceName: String = "", mode: String = "", headerType: String = "",
                allowInsecure: Bool = false, name: String = "") {
        self.kind = kind
        self.host = host
        self.port = port
        self.secret = secret
        self.method = method
        self.flow = flow
        self.network = network
        self.security = security
        self.sni = sni
        self.fingerprint = fingerprint
        self.alpn = alpn
        self.publicKey = publicKey
        self.shortId = shortId
        self.spiderX = spiderX
        self.path = path
        self.hostHeader = hostHeader
        self.serviceName = serviceName
        self.mode = mode
        self.headerType = headerType
        self.allowInsecure = allowInsecure
        self.name = name
    }

    /// host:port — так сервер показывается в окне и в отчёте.
    public var endpoint: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    /// Как назвать протокол человеку.
    public var title: String {
        let base: String
        switch kind {
        case .vless: base = "VLESS"
        case .vmess: base = "VMess"
        case .trojan: base = "Trojan"
        case .shadowsocks: base = "Shadowsocks"
        }
        switch security {
        case "reality": return "X-Ray (\(base) Reality)"
        case "tls": return "X-Ray (\(base) TLS)"
        default: return "X-Ray (\(base))"
        }
    }

    // MARK: - Разбор

    static let schemes = ["vless://", "vmess://", "trojan://", "ss://"]

    /// Похож ли текст на ключ X-Ray.
    public static func looksLikeLink(_ input: String) -> Bool {
        find(in: input) != nil
    }

    /// Ссылка из текста: целиком или внутри письма.
    public static func find(in input: String) -> String? {
        let lower = input.lowercased()
        var best: (String.Index, String)?
        for scheme in schemes {
            if let range = lower.range(of: scheme) {
                if best == nil || range.lowerBound < best!.0 { best = (range.lowerBound, scheme) }
            }
        }
        guard let (start, _) = best else { return nil }
        // Индексы в lower и в input совпадают: lowercased() для ASCII-схем
        // длину не меняет, а до схемы мы ничего не берём.
        let offset = lower.distance(from: lower.startIndex, to: start)
        let tail = input.dropFirst(offset)
        let link = tail.prefix { !$0.isWhitespace && $0 != "\"" && $0 != "'" && $0 != "<" && $0 != ">" }
        return link.isEmpty ? nil : String(link)
    }

    public static func parse(_ input: String) throws -> XrayLink {
        guard let link = find(in: input) else { throw ParseError.notALink }
        let lower = link.lowercased()
        if lower.hasPrefix("vmess://") { return try parseVmess(link) }
        if lower.hasPrefix("ss://") { return try parseShadowsocks(link) }
        if lower.hasPrefix("vless://") { return try parseUserInfo(link, kind: .vless) }
        if lower.hasPrefix("trojan://") { return try parseUserInfo(link, kind: .trojan) }
        throw ParseError.notALink
    }

    /// vless://UUID@host:port?параметры#имя и trojan://пароль@host:port?...
    private static func parseUserInfo(_ link: String, kind: Kind) throws -> XrayLink {
        let afterScheme = String(link[link.range(of: "://")!.upperBound...])
        let (body, fragment) = split(afterScheme, at: "#")
        let (authority, query) = split(body, at: "?")

        guard let at = authority.lastIndex(of: "@") else { throw ParseError.missing("идентификатора") }
        let secret = decode(String(authority[..<at]))
        let hostPort = String(authority[authority.index(after: at)...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !secret.isEmpty else { throw ParseError.missing("идентификатора") }
        let (host, port) = try splitHostPort(hostPort)

        let params = queryItems(query)
        var result = XrayLink(kind: kind, host: host, port: port, secret: secret, name: decode(fragment))
        result.flow = params["flow"] ?? ""
        result.method = params["encryption"] ?? ""
        result.network = normalizedNetwork(params["type"] ?? "tcp")
        result.security = (params["security"] ?? (kind == .trojan ? "tls" : "none")).lowercased()
        result.sni = params["sni"] ?? params["peer"] ?? ""
        result.fingerprint = params["fp"] ?? ""
        result.alpn = (params["alpn"] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
        result.publicKey = params["pbk"] ?? ""
        result.shortId = params["sid"] ?? ""
        result.spiderX = params["spx"] ?? ""
        result.path = params["path"] ?? ""
        result.hostHeader = params["host"] ?? ""
        result.serviceName = params["servicename"] ?? params["serviceName"] ?? ""
        result.mode = params["mode"] ?? ""
        result.headerType = params["headertype"] ?? params["headerType"] ?? ""
        result.allowInsecure = ["1", "true"].contains((params["allowinsecure"] ?? params["insecure"] ?? "").lowercased())
        try result.validate()
        return result
    }

    /// vmess://base64({"add":…,"port":…,"id":…,"net":…,"tls":…})
    private static func parseVmess(_ link: String) throws -> XrayLink {
        let encoded = String(link.dropFirst("vmess://".count)).components(separatedBy: "#")[0]
        guard let data = base64(encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.unsupported("vmess без JSON внутри")
        }
        func text(_ key: String) -> String {
            if let value = object[key] as? String { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
            return ""
        }
        guard let port = Int(text("port")) else { throw ParseError.missing("порта") }
        var result = XrayLink(kind: .vmess, host: text("add"), port: port, secret: text("id"), name: text("ps"))
        result.method = text("scy").isEmpty ? "auto" : text("scy")
        result.network = normalizedNetwork(text("net").isEmpty ? "tcp" : text("net"))
        result.security = text("tls").isEmpty ? "none" : text("tls").lowercased()
        result.sni = text("sni")
        result.fingerprint = text("fp")
        result.alpn = text("alpn").split(separator: ",").map(String.init)
        result.path = text("path")
        result.hostHeader = text("host")
        result.headerType = text("type")
        if result.network == "grpc" { result.serviceName = text("path") }
        try result.validate()
        return result
    }

    /// ss://base64(метод:пароль)@host:port#имя или ss://base64(метод:пароль@host:port)#имя
    private static func parseShadowsocks(_ link: String) throws -> XrayLink {
        let (body, fragment) = split(String(link.dropFirst("ss://".count)), at: "#")
        let (main, _) = split(body, at: "?")
        var userInfo: String
        var hostPort: String
        if let at = main.lastIndex(of: "@") {
            userInfo = decode(String(main[..<at]))
            hostPort = String(main[main.index(after: at)...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !userInfo.contains(":"), let data = base64(userInfo), let plain = String(data: data, encoding: .utf8) {
                userInfo = plain
            }
        } else {
            guard let data = base64(main), let plain = String(data: data, encoding: .utf8),
                  let at = plain.lastIndex(of: "@") else { throw ParseError.missing("адреса сервера") }
            userInfo = String(plain[..<at])
            hostPort = String(plain[plain.index(after: at)...])
        }
        guard let colon = userInfo.firstIndex(of: ":") else { throw ParseError.missing("пароля") }
        let (host, port) = try splitHostPort(hostPort)
        var result = XrayLink(kind: .shadowsocks, host: host, port: port,
                              secret: String(userInfo[userInfo.index(after: colon)...]),
                              name: decode(fragment))
        result.method = String(userInfo[..<colon])
        try result.validate()
        return result
    }

    private func validate() throws {
        guard !host.isEmpty else { throw ParseError.missing("адреса сервера") }
        guard (1...65535).contains(port) else { throw ParseError.missing("порта") }
        guard !secret.isEmpty else { throw ParseError.missing(kind == .vless || kind == .vmess ? "идентификатора" : "пароля") }
        let networks = ["tcp", "ws", "grpc", "xhttp", "httpupgrade", "kcp"]
        guard networks.contains(network) else { throw ParseError.unsupported("type=\(network)") }
        guard ["none", "tls", "reality"].contains(security) else { throw ParseError.unsupported("security=\(security)") }
        if security == "reality" && publicKey.isEmpty { throw ParseError.missing("ключа Reality (pbk)") }
        if kind == .shadowsocks && method.isEmpty { throw ParseError.missing("метода шифрования") }
    }

    // MARK: - Мелочи

    private static func normalizedNetwork(_ value: String) -> String {
        switch value.lowercased() {
        case "raw", "": return "tcp"
        case "splithttp": return "xhttp"
        case "websocket": return "ws"
        case "mkcp": return "kcp"
        default: return value.lowercased()
        }
    }

    private static func split(_ text: String, at separator: Character) -> (String, String) {
        guard let index = text.firstIndex(of: separator) else { return (text, "") }
        return (String(text[..<index]), String(text[text.index(after: index)...]))
    }

    private static func splitHostPort(_ value: String) throws -> (String, Int) {
        var text = value
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { throw ParseError.missing("адреса сервера") }
            let host = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            guard rest.hasPrefix(":"), let port = Int(rest.dropFirst()) else { throw ParseError.missing("порта") }
            return (host, port)
        }
        guard let colon = text.lastIndex(of: ":"), let port = Int(text[text.index(after: colon)...]) else {
            throw ParseError.missing("порта")
        }
        return (String(text[..<colon]), port)
    }

    /// Параметры запроса. Ключи — без учёта регистра, значения раскодированы.
    private static func queryItems(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let (key, value) = split(String(pair), at: "=")
            guard !key.isEmpty else { continue }
            result[key.lowercased()] = decode(value)
            result[key] = decode(value)
        }
        return result
    }

    private static func decode(_ value: String) -> String {
        (value.replacingOccurrences(of: "+", with: "%20").removingPercentEncoding ?? value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// base64 обычный и «для ссылок», с отрезанными «=» или без.
    static func base64(_ value: String) -> Data? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        text = text.removingPercentEncoding ?? text
        while text.count % 4 != 0 { text += "=" }
        return Data(base64Encoded: text)
    }
}
