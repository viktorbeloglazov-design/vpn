import Foundation
import KupibasCore

struct DefaultRoute {
    let gateway: String
    let interfaceName: String
}

/// Сколько файлов и сокетов открыто у самой службы.
///
/// Нужно затем, чтобы не гадать. По журналу с Mac видно: сначала служба
/// перестаёт видеть маршрут по умолчанию, потом не может создать
/// собственный временный файл — «Не удалось записать .status.json.tmp».
/// Папка на месте, права на месте, а запись не удаётся. Так выглядит
/// процесс, у которого кончились дескрипторы: запустить программу он
/// больше не может, открыть файл тоже, и лечится это только запуском
/// заново.
///
/// Проверить догадку можно только цифрой, и взять её надо тем способом,
/// который сам дескрипторов не требует, — иначе в нужный момент он
/// откажет первым. Поэтому никаких запусков программ: просто спрашиваем
/// у ядра про каждый номер по очереди.
enum OpenFiles {

    /// Сколько дескрипторов занято и каков потолок.
    static func count() -> (used: Int, limit: Int) {
        var limits = rlimit()
        let limit = getrlimit(RLIMIT_NOFILE, &limits) == 0
            ? Int(limits.rlim_cur)
            : Int(getdtablesize())

        // Потолок бывает «без ограничений» — перебирать столько незачем.
        let ceiling = min(limit, 65_536)
        var used = 0
        for descriptor in 0..<Int32(ceiling) where fcntl(descriptor, F_GETFD) != -1 {
            used += 1
        }
        return (used, limit)
    }

    /// Строка для журнала.
    static func text() -> String {
        let (used, limit) = count()
        return "открыто файлов и сокетов: \(used) из \(limit)"
    }
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

    /// Сеть, в которой сейчас находится интерфейс.
    ///
    /// Нужна, чтобы не проложить маршрут через шлюз, которого в нынешней
    /// сети нет: человек с ноутбуком переезжает, и запомненный шлюз
    /// остаётся от прошлой сети. Адрес и маску спрашиваем у интерфейса
    /// в тот же момент, а не берём из памяти.
    static func network(ofInterface name: String) -> Ipv4Net? {
        guard !name.isEmpty else { return nil }
        let result = Shell.runTool("ifconfig", [name], timeout: 10)
        guard result.succeeded else { return nil }

        for line in result.stdout.split(separator: "\n") {
            // Строки ifconfig начинаются с табуляции, а поля разделены
            // и пробелами, и табами — делим по любому пробельному знаку.
            let parts = line
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)

            guard let inetAt = parts.firstIndex(of: "inet"),
                  parts.count > inetAt + 1,
                  let address = Cidr.parseAddress(parts[inetAt + 1])
            else { continue }

            // Маска идёт шестнадцатеричной: netmask 0xffffff00.
            guard let maskAt = parts.firstIndex(of: "netmask"),
                  parts.count > maskAt + 1,
                  let mask = UInt32(parts[maskAt + 1].replacingOccurrences(of: "0x", with: ""),
                                    radix: 16)
            else { continue }

            // Длина префикса — число единиц в маске. Заодно убеждаемся,
            // что единицы идут подряд слева: иначе это не маска сети.
            let prefix = mask.nonzeroBitCount
            let rebuilt: UInt32 = prefix == 0 ? 0 : ~((UInt32(1) << (32 - UInt32(prefix))) - 1)
            guard rebuilt == mask else { continue }

            return Ipv4Net(start: address & mask, prefix: prefix)
        }
        return nil
    }

    /// Прокладывает маршрут по умолчанию заново.
    ///
    /// Обычно его ставит сама система, и трогать это не нужно. Но после
    /// опускания туннеля маршрут иногда не возвращается — и тогда
    /// интернета нет ни через VPN, ни мимо него, пока службу
    /// не перезапустят. В таком случае прокладываем его сами, тем же
    /// путём, каким он шёл до подъёма туннеля.
    @discardableResult
    static func addDefaultRoute(gateway: String, interfaceName: String) -> CommandResult {
        var arguments = ["-n", "add", "-inet", "default"]
        if !gateway.isEmpty {
            arguments.append(gateway)
        } else {
            arguments.append(contentsOf: ["-interface", interfaceName])
        }
        return Shell.runTool("route", arguments, timeout: 10)
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

    /// Переводит туннель на другой вход, не пересоздавая его.
    @discardableResult
    static func setPeerEndpoint(interface name: String, peerKey: String, endpoint: String) -> CommandResult {
        Shell.runTool("wg", ["set", name, "peer", peerKey, "endpoint", endpoint], timeout: 15)
    }

    /// Меняет размер пакета на лету: интерфейс при этом остаётся на месте.
    @discardableResult
    static func setMTU(interface name: String, mtu: Int) -> CommandResult {
        Shell.runTool("ifconfig", [name, "mtu", String(mtu)], timeout: 15)
    }

    static func interfaceExists(_ name: String) -> Bool {
        Shell.runTool("ifconfig", [name], timeout: 10).succeeded
    }
}
