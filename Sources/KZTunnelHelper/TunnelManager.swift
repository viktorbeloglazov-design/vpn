import Foundation
import KZTunnelCore

/// Приводит фактическое состояние сети к тому, что записано в config.json.
///
/// Обмен с GUI идёт только через файлы: GUI пишет config.json, демон читает его
/// раз в секунду и публикует status.json. Никаких сокетов и привилегированных
/// XPC-сервисов — меньше кода, который может сломаться под root.
final class TunnelManager {

    private let log: Logger

    // Что уже применено
    private var appliedRestartSignature = ""
    private var appliedRulesSignature = ""
    private var isUp = false
    private var state: TunnelState = .disconnected
    private var message = ""

    // Сетевое состояние, которое нужно вернуть на место при выключении
    private var savedDefaultRoute: DefaultRoute?
    private var savedDefaultRouteV6: DefaultRoute?
    private var servicesWithIPv6Disabled: [String] = []

    // Маршруты, которыми управляет демон
    private var bypassRoutes: Set<String> = []   // exclude: мимо туннеля, через физический шлюз
    private var tunnelRoutes: Set<String> = []   // include: в туннель
    private var realInterfaceName = ""

    private var connectedSince: Double = 0
    private var lastResolveAt = Date.distantPast
    private var lastRestartAt = Date.distantPast
    private var lastStatusWrite = Date.distantPast

    init(log: Logger) {
        self.log = log
    }

    // MARK: - Жизненный цикл

    /// После падения или перезагрузки демона в системе мог остаться поднятый туннель.
    func recoverOnStartup() {
        if FileManager.default.fileExists(atPath: Paths.wgConfigFile),
           NetworkTool.interfaceExists(Paths.interfaceName) {
            log.info("Обнаружен туннель от прошлого запуска — опускаю его.")
            _ = Shell.runTool("wg-quick", ["down", Paths.wgConfigFile])
        }
    }

    func shutdown() {
        if isUp {
            log.info("Завершение работы: опускаю туннель.")
            bringDown()
        }
        publishStatus(config: ConfigStore.loadConfig())
    }

    // MARK: - Основной цикл

    func tick() {
        let config = ConfigStore.loadConfig()

        if config.enabled {
            if let error = config.server.validationError {
                if isUp { bringDown() }
                state = .error
                message = error
            } else if !isUp {
                bringUp(config)
            } else if config.restartSignature != appliedRestartSignature {
                log.info("Изменились параметры подключения — перезапуск туннеля.")
                bringDown()
                bringUp(config)
            } else {
                if config.rulesSignature != appliedRulesSignature || needsReresolve(config) {
                    applyRules(config)
                }
                monitorHealth(config)
            }
        } else {
            if isUp { bringDown() }
            state = .disconnected
            message = ""
        }

        publishStatus(config: config)
    }

    // MARK: - Подъём туннеля

    private func bringUp(_ config: TunnelConfig) {
        state = .connecting
        message = ""
        publishStatus(config: config)

        guard Shell.which("wg-quick") != nil, Shell.which("wg") != nil else {
            state = .error
            message = "Не найдены wg-quick и wg. Установите: brew install wireguard-tools"
            log.error(message)
            return
        }
        guard Shell.which("wireguard-go") != nil else {
            state = .error
            message = "Не найден wireguard-go. Установите: brew install wireguard-go"
            log.error(message)
            return
        }

        // Снимаем маршрут по умолчанию до того, как его перебьёт туннель.
        savedDefaultRoute = NetworkTool.defaultRoute()
        savedDefaultRouteV6 = NetworkTool.defaultRoute(ipv6: true)
        if savedDefaultRoute == nil {
            state = .error
            message = "Нет подключения к интернету: маршрут по умолчанию не найден."
            log.error(message)
            return
        }

        let resolved = resolveRules(config)
        let allowedIPs = allowedIPsFor(config: config, resolved: resolved)

        let includeDNS = config.options.useTunnelDNS
            && !config.server.dns.isEmpty
            && config.mode != .include
        let text = WireGuardConfig.render(server: config.server,
                                          allowedIPs: allowedIPs,
                                          includeDNS: includeDNS)

        do {
            try FileManager.default.createDirectory(atPath: Paths.runtimeDir,
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: NSNumber(value: Int16(0o700))])
            try ConfigStore.writeAtomically(data: Data(text.utf8),
                                            to: Paths.wgConfigFile,
                                            permissions: 0o600)
        } catch {
            state = .error
            message = "Не удалось подготовить конфиг WireGuard: \(error.localizedDescription)"
            log.error(message)
            return
        }

        let result = Shell.runTool("wg-quick", ["up", Paths.wgConfigFile], timeout: 60)
        guard result.succeeded else {
            state = .error
            message = "wg-quick up: \(result.failureText)"
            log.error(message)
            _ = Shell.runTool("wg-quick", ["down", Paths.wgConfigFile], timeout: 30)
            return
        }

        isUp = true
        connectedSince = Date().timeIntervalSince1970
        realInterfaceName = NetworkTool.realInterfaceName(for: Paths.interfaceName) ?? ""
        appliedRestartSignature = config.restartSignature
        appliedRulesSignature = config.rulesSignature
        lastResolveAt = Date()
        bypassRoutes = []
        tunnelRoutes = []

        switch config.mode {
        case .full:
            break
        case .include:
            // Маршруты для AllowedIPs wg-quick уже поставил — фиксируем их как свои.
            tunnelRoutes = resolved
        case .exclude:
            installBypassRoutes(resolved)
        }

        if config.options.disableIPv6 && !config.server.hasIPv6Address && config.mode != .include {
            disableIPv6()
        }

        state = .connecting
        message = ""
        log.info("Туннель поднят (\(config.mode.rawValue), интерфейс \(realInterfaceName.isEmpty ? Paths.interfaceName : realInterfaceName), правил: \(resolved.count)).")
    }

    // MARK: - Опускание туннеля

    private func bringDown() {
        for cidr in bypassRoutes {
            _ = NetworkTool.deleteRoute(cidr)
        }
        bypassRoutes = []
        tunnelRoutes = []

        if FileManager.default.fileExists(atPath: Paths.wgConfigFile) {
            let result = Shell.runTool("wg-quick", ["down", Paths.wgConfigFile], timeout: 60)
            if !result.succeeded {
                log.error("wg-quick down: \(result.failureText)")
            }
        }

        restoreIPv6()

        isUp = false
        realInterfaceName = ""
        connectedSince = 0
        appliedRestartSignature = ""
        appliedRulesSignature = ""
        log.info("Туннель опущен.")
    }

    // MARK: - Правила маршрутизации

    private func needsReresolve(_ config: TunnelConfig) -> Bool {
        guard config.activeRules.contains(where: { $0.kind == .domain }) else { return false }
        let minutes = min(max(config.options.reresolveMinutes, 1), 60)
        return Date().timeIntervalSince(lastResolveAt) > Double(minutes) * 60
    }

    /// Разворачивает правила в набор подсетей, которые можно скормить маршрутизатору.
    private func resolveRules(_ config: TunnelConfig) -> Set<String> {
        var result: Set<String> = []
        // В режиме include адрес должен быть достижим через туннель, в остальных —
        // через физический канал, которого при отключённом IPv6 просто нет.
        let allowIPv6 = config.mode == .include
            ? config.server.hasIPv6Address
            : (savedDefaultRouteV6 != nil && !config.options.disableIPv6)

        for rule in config.activeRules {
            switch rule.kind {
            case .cidr:
                if let cidr = Validation.normalizeCIDR(rule.value) {
                    if cidr.contains(":") && !allowIPv6 { continue }
                    result.insert(cidr)
                }
            case .domain:
                let host = rule.value.trimmingCharacters(in: .whitespaces).lowercased()
                guard Validation.isDomain(host) else { continue }
                var addresses = Resolver.resolve(host)
                // Для доменов вида example.com полезно захватить и www-вариант.
                if !host.hasPrefix("www.") && host.split(separator: ".").count == 2 {
                    addresses.append(contentsOf: Resolver.resolve("www." + host))
                }
                for address in addresses {
                    if address.contains(":") && !allowIPv6 { continue }
                    if let cidr = Validation.normalizeCIDR(address) {
                        result.insert(cidr)
                    }
                }
            }
        }
        return result
    }

    private func allowedIPsFor(config: TunnelConfig, resolved: Set<String>) -> [String] {
        switch config.mode {
        case .full, .exclude:
            var list = ["0.0.0.0/0"]
            if config.server.hasIPv6Address { list.append("::/0") }
            return list
        case .include:
            if resolved.isEmpty {
                // Пустой AllowedIPs wg-quick не примет: ставим адрес самого клиента —
                // он никуда не ведёт, туннель просто стоит пустым.
                return [Validation.normalizeCIDR(config.server.addresses.first ?? "10.0.0.1/32") ?? "10.0.0.1/32"]
            }
            return resolved.sorted()
        }
    }

    private func applyRules(_ config: TunnelConfig) {
        let desired = resolveRules(config)
        lastResolveAt = Date()
        appliedRulesSignature = config.rulesSignature

        switch config.mode {
        case .full:
            return

        case .exclude:
            let toAdd = desired.subtracting(bypassRoutes)
            let toRemove = bypassRoutes.subtracting(desired)
            for cidr in toRemove {
                _ = NetworkTool.deleteRoute(cidr)
                bypassRoutes.remove(cidr)
            }
            installBypassRoutes(toAdd)
            if !toAdd.isEmpty || !toRemove.isEmpty {
                log.info("Исключения обновлены: +\(toAdd.count) / -\(toRemove.count).")
            }

        case .include:
            let toAdd = desired.subtracting(tunnelRoutes)
            let toRemove = tunnelRoutes.subtracting(desired)
            guard !toAdd.isEmpty || !toRemove.isEmpty else { return }

            let allowed = allowedIPsFor(config: config, resolved: desired)
            let result = NetworkTool.setAllowedIPs(interface: Paths.interfaceName,
                                                   peerKey: config.server.publicKey,
                                                   allowedIPs: allowed)
            if !result.succeeded {
                log.error("wg set allowed-ips: \(result.failureText)")
                return
            }

            for cidr in toRemove {
                _ = NetworkTool.deleteRoute(cidr)
                tunnelRoutes.remove(cidr)
            }
            let interfaceName = realInterfaceName.isEmpty ? Paths.interfaceName : realInterfaceName
            for cidr in toAdd {
                let add = NetworkTool.addRoute(cidr, interfaceName: interfaceName)
                if add.succeeded || add.failureText.contains("File exists") {
                    tunnelRoutes.insert(cidr)
                } else {
                    log.error("route add \(cidr) -> \(interfaceName): \(add.failureText)")
                }
            }
            log.info("Маршруты в туннель обновлены: +\(toAdd.count) / -\(toRemove.count).")
        }
    }

    private func installBypassRoutes(_ cidrs: Set<String>) {
        for cidr in cidrs {
            let isIPv6 = cidr.contains(":")
            guard let via = isIPv6 ? savedDefaultRouteV6 : savedDefaultRoute else { continue }
            let result = NetworkTool.addRoute(cidr, via: via)
            if result.succeeded || result.failureText.contains("File exists") {
                bypassRoutes.insert(cidr)
            } else {
                log.error("route add \(cidr) -> \(via.gateway): \(result.failureText)")
            }
        }
    }

    // MARK: - Контроль соединения

    private func monitorHealth(_ config: TunnelConfig) {
        guard let stats = NetworkTool.peerStats(interface: Paths.interfaceName) else {
            // Интерфейс исчез (например, его снесли вручную) — поднимаем заново.
            log.error("Интерфейс \(Paths.interfaceName) недоступен — переподключение.")
            bringDown()
            return
        }

        let now = Date().timeIntervalSince1970
        if stats.lastHandshake > 0 {
            state = (now - stats.lastHandshake) < 180 ? .connected : .connecting
        } else {
            state = .connecting
        }

        guard config.options.autoReconnect else { return }
        guard Date().timeIntervalSince(lastRestartAt) > 60 else { return }

        let stalled: Bool
        if stats.lastHandshake > 0 {
            stalled = (now - stats.lastHandshake) > 180
        } else {
            stalled = (now - connectedSince) > 40
        }
        if stalled {
            lastRestartAt = Date()
            log.error("Нет handshake с сервером — перезапуск туннеля.")
            message = "Сервер не отвечает, переподключаюсь…"
            bringDown()
        }
    }

    // MARK: - IPv6

    private func disableIPv6() {
        var disabled: [String] = []
        for service in NetworkTool.networkServices() where NetworkTool.isIPv6Enabled(service: service) {
            let result = NetworkTool.setIPv6(service: service, enabled: false)
            if result.succeeded { disabled.append(service) }
        }
        servicesWithIPv6Disabled = disabled
        if !disabled.isEmpty {
            log.info("IPv6 временно отключён: \(disabled.joined(separator: ", ")).")
        }
    }

    private func restoreIPv6() {
        for service in servicesWithIPv6Disabled {
            _ = NetworkTool.setIPv6(service: service, enabled: true)
        }
        if !servicesWithIPv6Disabled.isEmpty {
            log.info("IPv6 возвращён: \(servicesWithIPv6Disabled.joined(separator: ", ")).")
        }
        servicesWithIPv6Disabled = []
    }

    // MARK: - Публикация статуса

    private func publishStatus(config: TunnelConfig) {
        var status = TunnelStatus()
        status.state = state
        status.mode = config.mode
        status.interfaceName = realInterfaceName.isEmpty ? Paths.interfaceName : realInterfaceName
        status.serverName = config.server.name
        status.endpoint = config.server.endpoint
        status.connectedSince = connectedSince
        status.message = message
        status.updatedAt = Date().timeIntervalSince1970

        if isUp, let stats = NetworkTool.peerStats(interface: Paths.interfaceName) {
            status.lastHandshake = stats.lastHandshake
            status.rxBytes = stats.rxBytes
            status.txBytes = stats.txBytes
        }

        switch config.mode {
        case .full: status.routeCount = 0
        case .include: status.routeCount = tunnelRoutes.count
        case .exclude: status.routeCount = bypassRoutes.count
        }

        do {
            try ConfigStore.saveStatus(status)
            lastStatusWrite = Date()
        } catch {
            if Date().timeIntervalSince(lastStatusWrite) > 60 {
                lastStatusWrite = Date()
                log.error("Не удалось записать статус: \(error.localizedDescription)")
            }
        }
    }
}
