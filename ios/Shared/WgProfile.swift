import Foundation

/// Разобранный профиль WireGuard или AmneziaWG.
struct WgProfile {

    /// Имена параметров маскировки так, как их ждёт библиотека AmneziaWG.
    static let amneziaFields: [(key: String, name: String)] = [
        ("jc", "Jc"), ("jmin", "Jmin"), ("jmax", "Jmax"),
        ("s1", "S1"), ("s2", "S2"), ("s3", "S3"), ("s4", "S4"),
        ("h1", "H1"), ("h2", "H2"), ("h3", "H3"), ("h4", "H4"),
        ("i1", "I1"), ("i2", "I2"), ("i3", "I3"), ("i4", "I4"), ("i5", "I5"),
    ]

    var privateKey: String
    var addresses: [String]
    var dns: [String]
    var mtu: Int
    var publicKey: String
    var presharedKey: String
    var endpoint: String
    var keepalive: Int

    /// Параметры маскировки AmneziaWG, если они были в файле.
    var amneziaParams: [String: String]

    var isAmnezia: Bool { !amneziaParams.isEmpty }
    var protocolName: String { isAmnezia ? "AmneziaWG" : "WireGuard" }

    var endpointHost: String {
        guard let colon = endpoint.lastIndex(of: ":") else { return endpoint }
        return String(endpoint[endpoint.startIndex..<colon])
    }

    enum ParseError: LocalizedError {
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .missing(let what): return what
            }
        }
    }

    /// Собирает текст настроек для туннеля.
    ///
    /// AllowedIPs здесь — главное: именно этот список решает, что пойдёт
    /// в туннель.
    func configText(allowedIps: [String], includeDns: Bool) -> String {
        var lines: [String] = []
        lines.append("[Interface]")
        lines.append("PrivateKey = \(privateKey)")
        lines.append("Address = \(addresses.joined(separator: ", "))")
        lines.append("MTU = \(mtu)")
        if includeDns && !dns.isEmpty {
            lines.append("DNS = \(dns.joined(separator: ", "))")
        }
        for (key, name) in Self.amneziaFields {
            if let value = amneziaParams[key] {
                lines.append("\(name) = \(value)")
            }
        }
        lines.append("")
        lines.append("[Peer]")
        lines.append("PublicKey = \(publicKey)")
        if !presharedKey.isEmpty {
            lines.append("PresharedKey = \(presharedKey)")
        }
        lines.append("Endpoint = \(endpoint)")
        lines.append("AllowedIPs = \(allowedIps.joined(separator: ", "))")
        if keepalive > 0 {
            lines.append("PersistentKeepalive = \(keepalive)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parse(_ text: String) throws -> WgProfile {
        var section = ""
        var interface: [String: String] = [:]
        var peer: [String: String] = [:]

        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") {
                line = String(line[line.startIndex..<hash])
            }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = line.dropFirst().dropLast().lowercased()
                continue
            }

            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)

            if section == "interface" { interface[key] = value }
            else if section == "peer" { peer[key] = value }
        }

        guard !interface.isEmpty else { throw ParseError.missing("В настройках нет раздела [Interface].") }
        guard !peer.isEmpty else { throw ParseError.missing("В настройках нет раздела [Peer].") }

        guard let privateKey = interface["privatekey"], !privateKey.isEmpty else {
            throw ParseError.missing("В настройках нет приватного ключа.")
        }
        guard let publicKey = peer["publickey"], !publicKey.isEmpty else {
            throw ParseError.missing("В настройках нет публичного ключа сервера.")
        }
        guard let endpoint = peer["endpoint"], !endpoint.isEmpty else {
            throw ParseError.missing("В настройках нет адреса сервера (Endpoint).")
        }

        var amnezia: [String: String] = [:]
        for (key, _) in amneziaFields {
            if let value = interface[key], !value.isEmpty { amnezia[key] = value }
        }

        return WgProfile(
            privateKey: privateKey,
            addresses: splitList(interface["address"]),
            dns: splitList(interface["dns"]),
            mtu: Int(interface["mtu"] ?? "") ?? 1420,
            publicKey: publicKey,
            presharedKey: peer["presharedkey"] ?? "",
            endpoint: endpoint,
            keepalive: Int(peer["persistentkeepalive"] ?? "") ?? 25,
            amneziaParams: amnezia
        )
    }

    private static func splitList(_ value: String?) -> [String] {
        (value ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
