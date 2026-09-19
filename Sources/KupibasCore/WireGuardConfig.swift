import Foundation

/// Разбор и генерация конфигурации WireGuard в формате wg-quick.
public enum WireGuardConfig {

    public enum ParseError: LocalizedError {
        case noInterfaceSection
        case noPeerSection
        case missing(String)
        case invalid(String)

        public var errorDescription: String? {
            switch self {
            case .noInterfaceSection: return "В конфиге нет секции [Interface]."
            case .noPeerSection: return "В конфиге нет секции [Peer]."
            case .missing(let key): return "В конфиге не хватает поля \(key)."
            case .invalid(let text): return text
            }
        }
    }

    /// Разбирает текст вида .conf, который выдаёт сервер или VPN-провайдер.
    public static func parse(_ text: String, name: String = "KZ") throws -> ServerConfig {
        var section = ""
        var interface: [String: String] = [:]
        var peer: [String: String] = [:]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") { line = String(line[line.startIndex..<hash]) }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = line.dropFirst().dropLast().lowercased()
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<equals]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if section == "interface" {
                interface[key] = value
            } else if section == "peer" {
                // Поддерживаем только одного пира — этого достаточно для схемы «клиент → сервер».
                if peer[key] == nil { peer[key] = value }
            }
        }

        if interface.isEmpty { throw ParseError.noInterfaceSection }
        if peer.isEmpty { throw ParseError.noPeerSection }

        guard let privateKey = interface["privatekey"], !privateKey.isEmpty else {
            throw ParseError.missing("PrivateKey")
        }
        guard let publicKey = peer["publickey"], !publicKey.isEmpty else {
            throw ParseError.missing("PublicKey")
        }
        guard let endpoint = peer["endpoint"], !endpoint.isEmpty else {
            throw ParseError.missing("Endpoint")
        }
        guard let addressLine = interface["address"], !addressLine.isEmpty else {
            throw ParseError.missing("Address")
        }

        var config = ServerConfig()
        config.name = name
        config.privateKey = privateKey
        config.publicKey = publicKey
        config.presharedKey = peer["presharedkey"] ?? ""
        config.endpoint = endpoint
        config.addresses = splitList(addressLine)
        config.dns = splitList(interface["dns"] ?? "").filter { Validation.isIPAddress($0) }
        if let mtu = interface["mtu"], let value = Int(mtu) { config.mtu = value }
        if let keepalive = peer["persistentkeepalive"], let value = Int(keepalive) {
            config.persistentKeepalive = value
        }

        if let error = config.validationError { throw ParseError.invalid(error) }
        return config
    }

    /// Собирает .conf для wg-quick. AllowedIPs подставляет вызывающая сторона —
    /// именно они определяют, что пойдёт в туннель.
    public static func render(server: ServerConfig,
                              allowedIPs: [String],
                              includeDNS: Bool) -> String {
        var lines: [String] = []
        lines.append("# Сгенерировано kupibasvpnd. Правки будут перезаписаны.")
        lines.append("[Interface]")
        lines.append("PrivateKey = \(server.privateKey)")
        lines.append("Address = \(server.addresses.joined(separator: ", "))")
        lines.append("MTU = \(server.mtu)")
        if includeDNS && !server.dns.isEmpty {
            lines.append("DNS = \(server.dns.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("[Peer]")
        lines.append("PublicKey = \(server.publicKey)")
        if !server.presharedKey.isEmpty {
            lines.append("PresharedKey = \(server.presharedKey)")
        }
        lines.append("Endpoint = \(server.endpoint)")
        lines.append("AllowedIPs = \(allowedIPs.joined(separator: ", "))")
        if server.persistentKeepalive > 0 {
            lines.append("PersistentKeepalive = \(server.persistentKeepalive)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func splitList(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
