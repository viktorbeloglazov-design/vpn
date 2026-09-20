import Foundation

struct DefaultRoute {
    let gateway: String
    let interfaceName: String
}

/// Тонкая обёртка над route/ifconfig/networksetup.
enum NetworkTool {

    // MARK: - Маршрут по умолчанию

    /// Текущий маршрут по умолчанию. Снимать его нужно до подъёма туннеля:
    /// после подъёма default уже указывает в utun.
    static func defaultRoute(ipv6: Bool = false) -> DefaultRoute? {
        var arguments = ["-n", "get"]
        if ipv6 { arguments.append("-inet6") }
        arguments.append("default")
        let result = Shell.runTool("route", arguments, timeout: 10)
        guard result.succeeded else { return nil }

        var gateway = ""
        var interfaceName = ""
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if key == "gateway" { gateway = value }
            if key == "interface" { interfaceName = value }
        }
        // На мобильном интернете шлюза может не быть — тогда маршрутизируем по интерфейсу.
        guard !gateway.isEmpty || !interfaceName.isEmpty else { return nil }
        if let percent = gateway.firstIndex(of: "%") {
            gateway = String(gateway[gateway.startIndex..<percent])
        }
        return DefaultRoute(gateway: gateway, interfaceName: interfaceName)
    }

    // MARK: - Маршруты

    @discardableResult
    static func addRoute(_ cidr: String, via route: DefaultRoute) -> CommandResult {
        var arguments = ["-n", "add"]
        if cidr.contains(":") { arguments.append("-inet6") }
        arguments.append(contentsOf: ["-net", cidr])
        if !route.gateway.isEmpty {
            arguments.append(route.gateway)
        } else {
            arguments.append(contentsOf: ["-interface", route.interfaceName])
        }
        return Shell.runTool("route", arguments, timeout: 10)
    }

    @discardableResult
    static func addRoute(_ cidr: String, interfaceName: String) -> CommandResult {
        var arguments = ["-n", "add"]
        if cidr.contains(":") { arguments.append("-inet6") }
        arguments.append(contentsOf: ["-net", cidr, "-interface", interfaceName])
        return Shell.runTool("route", arguments, timeout: 10)
    }

    @discardableResult
    static func deleteRoute(_ cidr: String) -> CommandResult {
        var arguments = ["-n", "delete"]
        if cidr.contains(":") { arguments.append("-inet6") }
        arguments.append(contentsOf: ["-net", cidr])
        return Shell.runTool("route", arguments, timeout: 10)
    }

    // MARK: - Сетевые службы и IPv6

    /// Активные службы (Wi-Fi, Ethernet, …). Отключённые (со звёздочкой) пропускаем.
    static func networkServices() -> [String] {
        let result = Shell.runTool("networksetup", ["-listallnetworkservices"], timeout: 15)
        guard result.succeeded else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") && !$0.lowercased().hasPrefix("an asterisk") }
    }

    static func isIPv6Enabled(service: String) -> Bool {
        let result = Shell.runTool("networksetup", ["-getinfo", service], timeout: 15)
        guard result.succeeded else { return false }
        for line in result.stdout.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("IPv6:") {
                return !text.lowercased().contains("off")
            }
        }
        return false
    }

    @discardableResult
    static func setIPv6(service: String, enabled: Bool) -> CommandResult {
        Shell.runTool("networksetup", [enabled ? "-setv6automatic" : "-setv6off", service], timeout: 20)
    }

    // MARK: - Состояние WireGuard

    struct PeerStats {
        var lastHandshake: Double = 0
        var rxBytes: Int = 0
        var txBytes: Int = 0
        var endpoint: String = ""
    }

    /// Парсит `wg show <iface> dump`: первая строка — интерфейс, дальше пиры.
    static func peerStats(interface name: String) -> PeerStats? {
        let result = Shell.runTool("wg", ["show", name, "dump"], timeout: 10)
        guard result.succeeded else { return nil }
        let lines = result.stdout.split(separator: "\n")
        guard lines.count >= 2 else { return PeerStats() }
        let fields = lines[1].split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 8 else { return PeerStats() }
        var stats = PeerStats()
        stats.endpoint = fields[2] == "(none)" ? "" : fields[2]
        stats.lastHandshake = Double(fields[4]) ?? 0
        stats.rxBytes = Int(fields[5]) ?? 0
        stats.txBytes = Int(fields[6]) ?? 0
        return stats
    }

    /// Меняет AllowedIPs на лету — нужно в режиме «только правила через VPN».
    @discardableResult
    static func setAllowedIPs(interface name: String, peerKey: String, allowedIPs: [String]) -> CommandResult {
        let list = allowedIPs.isEmpty ? "0.0.0.0/32" : allowedIPs.joined(separator: ",")
        return Shell.runTool("wg", ["set", name, "peer", peerKey, "allowed-ips", list], timeout: 15)
    }

    static func interfaceExists(_ name: String) -> Bool {
        Shell.runTool("ifconfig", [name], timeout: 10).succeeded
    }
}
