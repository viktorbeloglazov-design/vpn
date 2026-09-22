import Foundation
import KupibasCore

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
    private var bypassRoutes: Set<String> = []
    /// Крупный список обхода: российская зона. Хранится подсетями, а не
    /// строками, — его тысячи, и снимать его нужно так же быстро.
    private var bulkBypass: Set<Ipv4Net> = []
    private var tunnelRoutes: Set<String> = []   // include: в туннель

    /// Маршруты, направленные в сам туннель, — их ставим вместо wg-quick.
    private var interfaceRoutes: Set<String> = []

    /// Маршрут до сервера через настоящий канал: без него зашифрованные
    /// пакеты пошли бы в туннель, который их же и несёт.
    private var endpointRoute = ""

    /// DNS сетевых служб до нашего вмешательства — их надо вернуть.
    private var savedDNS: [String: String] = [:]

    private var realInterfaceName = ""

    private var connectedSince: Double = 0
    private let link = LinkWatch()
    private var lastResolveAt = Date.distantPast
    private var lastRestartAt = Date.distantPast
    private var lastStatusWrite = Date.distantPast

    init(log: Logger) {
        self.log = log
    }

    // MARK: - Жизненный цикл

    /// После падения или перезагрузки демона в системе мог остаться поднятый туннель.
    func recoverOnStartup() {
        if let name = WireGuardInterface.existingInterface(logicalName: Paths.interfaceName) {
            log.info("Обнаружен туннель от прошлого запуска (\(name)) — опускаю его.")
            realInterfaceName = name
            tearDownInterface()
        }

        // И всё, что осталось от предыдущих запусков службы. Такие туннели
        // продолжают держать свои utun и мешают поднять новый.
        WireGuardInterface.cleanUpOrphans(logicalName: Paths.interfaceName)
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

        guard Shell.which("wg") != nil else {
            state = .error
            message = "Не найдена утилита wg — переустановите службу из приложения."
            log.error(message)
            return
        }
        guard Shell.which("amneziawg-go") != nil || Shell.which("wireguard-go") != nil else {
            state = .error
            message = "Не найден amneziawg-go — переустановите службу из приложения."
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
            && config.effectiveMode != .include
        let text = WireGuardConfig.render(server: config.server,
                                          allowedIPs: allowedIPs,
                                          includeDNS: includeDNS,
                                          mtuOverride: config.options.mtu)

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

        // 1. Создаём интерфейс. Имя utun выдаёт система, оно заранее неизвестно.
        let interfaceName: String
        switch WireGuardInterface.start(logicalName: Paths.interfaceName) {
        case .started(let name):
            interfaceName = name
        case .failed(let reason):
            state = .error
            message = reason
            log.error(message)
            WireGuardInterface.stop(interface: nil, logicalName: Paths.interfaceName)
            return
        }
        realInterfaceName = interfaceName
        log.info("Интерфейс \(Paths.interfaceName) — это \(interfaceName).")

        // 2. Ключи и список AllowedIPs.
        let setconf = WireGuardInterface.setConfig(
            interface: interfaceName,
            text: WireGuardConfig.renderForSetConf(server: config.server, allowedIPs: allowedIPs)
        )
        guard setconf.succeeded else {
            state = .error
            message = "Настройки туннеля не приняты: \(setconf.failureText)"
            log.error(message)
            tearDownInterface()
            return
        }

        // 3. Адрес клиента и размер пакета.
        for address in config.server.addresses {
            let result = WireGuardInterface.addAddress(interface: interfaceName, address: address)
            if !result.succeeded {
                log.error("ifconfig \(interfaceName) \(address): \(result.failureText)")
            }
        }
        let mtu = config.options.mtu > 0 ? config.options.mtu : config.server.mtu
        WireGuardInterface.setMTU(interface: interfaceName, mtu: mtu)
        WireGuardInterface.bringUp(interface: interfaceName)

        // 4. Маршрут до самого сервера — мимо туннеля, иначе он замкнётся сам на себя.
        if let via = savedDefaultRoute {
            let host = config.server.endpointHost
            if !host.isEmpty, !host.contains(":") {
                let destination = host + "/32"
                let result = NetworkTool.addRoute(destination, via: via)
                if result.succeeded || result.failureText.contains("File exists") {
                    endpointRoute = destination
                } else {
                    log.error("маршрут до сервера \(destination): \(result.failureText)")
                }
            }
        }

        // 5. Маршруты в туннель.
        interfaceRoutes = []
        for destination in WireGuardConfig.routeDestinations(for: allowedIPs) {
            let result = NetworkTool.addRoute(destination, interfaceName: interfaceName)
            if result.succeeded || result.failureText.contains("File exists") {
                interfaceRoutes.insert(destination)
            } else {
                log.error("маршрут \(destination) -> \(interfaceName): \(result.failureText)")
            }
        }

        // 6. DNS туннеля.
        if includeDNS {
            applyDNS(config.server.dns)
        }

        isUp = true
        connectedSince = Date().timeIntervalSince1970
        link.start(rx: 0, tx: 0, now: connectedSince)
        appliedRestartSignature = config.restartSignature
        appliedRulesSignature = config.rulesSignature
        lastResolveAt = Date()
        bypassRoutes = []
        tunnelRoutes = []

        switch config.effectiveMode {
        case .full:
            break
        case .include:
            // Маршруты для AllowedIPs уже проложены выше — фиксируем их как свои.
            tunnelRoutes = resolved
        case .exclude:
            // Правила пользователя по IPv6 — прежним путём, поштучно.
            installBypassRoutes(resolved.filter { $0.contains(":") })
            installBulkBypass(bypassNets(config, resolved: resolved))
        }

        if config.options.disableIPv6 && !config.server.hasIPv6Address && config.effectiveMode != .include {
            disableIPv6()
        }

        state = .connecting
        message = ""
        log.info("Туннель поднят (\(config.effectiveMode.rawValue), интерфейс \(realInterfaceName.isEmpty ? Paths.interfaceName : realInterfaceName), правил: \(resolved.count)).")

        verifyAndTune(config, interfaceName: interfaceName)
    }

    // MARK: - Проверка и подгонка

    /// Размеры пакета сверху вниз: чем больше, тем быстрее.
    ///
    /// 1280 — нижняя ступень: столько обязана пропускать любая сеть.
    private static let mtuLadder = [1420, 1380, 1320, 1280]

    /// Ждёт первого ответа сервера.
    private func waitForHandshake(seconds: Int) -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 1)
            if let stats = NetworkTool.peerStats(interface: realInterfaceName), stats.lastHandshake > 0 {
                return true
            }
        }
        return false
    }

    /// Доводит поднятый туннель до рабочего состояния.
    ///
    /// Сначала убеждаемся, что сервер вообще отвечает: не отвечает — пробуем
    /// запасной вход, если он задан. Потом проверяем, что проходят большие
    /// порции данных, и если нет — уменьшаем размер пакета. Всё это делается
    /// на живом интерфейсе: ни маршруты, ни адреса пересоздавать не нужно.
    private func verifyAndTune(_ config: TunnelConfig, interfaceName: String) {
        let entries = config.endpointsToTry()

        if !waitForHandshake(seconds: entries.count > 1 ? 12 : 20) {
            guard entries.count > 1 else {
                message = "Сервер \(config.server.endpointHost) не отвечает."
                log.error(message)
                return
            }
            let backup = entries[1]
            log.info("Сервер молчит — пробую запасной вход \(backup).")
            message = "Пробую запасной вход…"
            NetworkTool.setPeerEndpoint(interface: interfaceName,
                                        peerKey: config.server.publicKey,
                                        endpoint: backup)
            guard waitForHandshake(seconds: 20) else {
                message = "Ни сервер, ни запасной вход не отвечают."
                log.error(message)
                return
            }
            usedBackupEntry = true
            message = "Через запасной вход"
            log.info("Связь через запасной вход \(backup).")
        } else {
            usedBackupEntry = false
        }

        guard config.options.mtu == 0 else {
            activeMtu = config.options.mtu
            return
        }
        tuneMTU(config, interfaceName: interfaceName)
    }

    /// Подбирает размер пакета, пока не пойдут большие порции данных.
    private func tuneMTU(_ config: TunnelConfig, interfaceName: String) {
        let remembered = config.options.probedMtu
        let start = remembered > 0 ? remembered : min(config.server.mtu, Self.mtuLadder[0])
        // Повторов тут быть не может: ниже start берём только меньшие.
        let ladder = [start] + Self.mtuLadder.filter { $0 < start }

        var applied = config.server.mtu
        for mtu in ladder {
            if mtu != applied {
                log.info("Подбираю размер пакета: \(mtu).")
                NetworkTool.setMTU(interface: interfaceName, mtu: mtu)
                applied = mtu
            }
            if BulkCheck.works() {
                activeMtu = mtu
                if mtu != remembered {
                    var updated = ConfigStore.loadConfig()
                    updated.options.probedMtu = mtu
                    try? ConfigStore.saveConfig(updated)
                }
                log.info("Размер пакета \(mtu) — большие порции проходят.")
                return
            }
        }

        // Ни один размер не помог — значит, дело не в нём. Остаёмся на нижней
        // ступени: она хотя бы заведомо проходит.
        activeMtu = ladder.last ?? config.server.mtu
        log.error("Размер пакета не помог: большие порции не проходят ни при каком.")
    }

    /// Каким входом поднялась связь и с каким размером пакета.
    private(set) var usedBackupEntry = false
    private(set) var activeMtu = 0

    // MARK: - Опускание туннеля

    private func bringDown() {
        removeBulkBypass()
        for cidr in bypassRoutes {
            _ = NetworkTool.deleteRoute(cidr)
        }
        bypassRoutes = []
        tunnelRoutes = []

        tearDownInterface()
        restoreIPv6()

        isUp = false
        connectedSince = 0
        appliedRestartSignature = ""
        appliedRulesSignature = ""
        log.info("Туннель опущен.")
    }

    /// Снимает интерфейс и всё, что мы вокруг него поставили.
    private func tearDownInterface() {
        restoreDNS()

        for destination in interfaceRoutes {
            _ = NetworkTool.deleteRoute(destination)
        }
        interfaceRoutes = []

        if !endpointRoute.isEmpty {
            _ = NetworkTool.deleteRoute(endpointRoute)
            endpointRoute = ""
        }

        WireGuardInterface.stop(interface: realInterfaceName, logicalName: Paths.interfaceName)
        realInterfaceName = ""
    }

    // MARK: - DNS

    /// Переводит сетевые службы на DNS туннеля, запомнив прежние.
    ///
    /// Без своего DNS толку от туннеля мало: провайдер отвечает на
    /// заблокированные имена подставным российским адресом, а тот идёт мимо
    /// VPN — и сайт всё равно не открывается.
    private func applyDNS(_ servers: [String]) {
        guard !servers.isEmpty else { return }
        savedDNS = [:]

        for service in NetworkTool.networkServices() {
            let current = Shell.runTool("networksetup", ["-getdnsservers", service], timeout: 15)
            // Когда своих серверов нет, утилита отвечает целой фразой —
            // её нельзя записывать как адрес, вернуть надо слово Empty.
            let text = current.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            savedDNS[service] = text.contains(" ") || text.isEmpty ? "Empty" : text

            let result = Shell.runTool("networksetup", ["-setdnsservers", service] + servers, timeout: 20)
            if !result.succeeded {
                log.error("DNS для «\(service)»: \(result.failureText)")
            }
        }
        if !savedDNS.isEmpty {
            log.info("DNS туннеля: \(servers.joined(separator: ", ")) для \(savedDNS.count) служб.")
        }
    }

    private func restoreDNS() {
        for (service, previous) in savedDNS {
            let values = previous == "Empty" ? ["Empty"] : previous.split(separator: "\n").map(String.init)
            _ = Shell.runTool("networksetup", ["-setdnsservers", service] + values, timeout: 20)
        }
        savedDNS = [:]
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
        let allowIPv6 = config.effectiveMode == .include
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
        switch config.effectiveMode {
        case .full, .exclude:
            var list = ["0.0.0.0/0"]
            if config.server.hasIPv6Address { list.append("::/0") }
            return list
        case .include:
            if resolved.isEmpty {
                // Пустой AllowedIPs туннель не примет: ставим адрес самого клиента —
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

        switch config.effectiveMode {
        case .full:
            return

        case .exclude:
            let ipv6Rules = desired.filter { $0.contains(":") }
            let toAdd = ipv6Rules.subtracting(bypassRoutes)
            let toRemove = bypassRoutes.subtracting(ipv6Rules)
            for cidr in toRemove {
                _ = NetworkTool.deleteRoute(cidr)
                bypassRoutes.remove(cidr)
            }
            installBypassRoutes(toAdd)

            // Крупный список пересобираем разницей: снимать и ставить
            // тысячи маршрутов заново незачем.
            let wanted = Set(bypassNets(config, resolved: desired))
            let netsToAdd = wanted.subtracting(bulkBypass)
            let netsToRemove = bulkBypass.subtracting(wanted)

            if let via = savedDefaultRoute, !via.gateway.isEmpty {
                if !netsToRemove.isEmpty {
                    _ = RouteSocket.delete(Array(netsToRemove), gateway: via.gateway)
                }
                if !netsToAdd.isEmpty {
                    _ = RouteSocket.add(Array(netsToAdd), gateway: via.gateway)
                }
                bulkBypass = wanted
            }

            if !toAdd.isEmpty || !toRemove.isEmpty || !netsToAdd.isEmpty || !netsToRemove.isEmpty {
                log.info("Исключения обновлены: +\(toAdd.count + netsToAdd.count) / -\(toRemove.count + netsToRemove.count).")
            }

        case .include:
            let toAdd = desired.subtracting(tunnelRoutes)
            let toRemove = tunnelRoutes.subtracting(desired)
            guard !toAdd.isEmpty || !toRemove.isEmpty else { return }

            let allowed = allowedIPsFor(config: config, resolved: desired)
            let result = NetworkTool.setAllowedIPs(interface: realInterfaceName,
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

    /// Подсети, которые должны идти мимо туннеля.
    ///
    /// При включённом главном фильтре это вся российская зона плюс правила
    /// пользователя. Рабочие ресурсы из списка вычитаются: их адрес лежит
    /// в российской зоне, но уходить мимо VPN он не должен.
    private func bypassNets(_ config: TunnelConfig, resolved: Set<String>) -> [Ipv4Net] {
        var nets: [Ipv4Net] = resolved.compactMap { cidr in
            cidr.contains(":") ? nil : Cidr.parse(cidr)
        }

        if config.mainFilter {
            nets += RuZone.networks()
        }

        guard !nets.isEmpty else { return [] }

        if config.workFilter {
            let work = WorkFilter.hosts.compactMap { Cidr.parse($0) }
            if !work.isEmpty {
                return Cidr.subtract(nets, work)
            }
        }
        return Cidr.merge(nets)
    }

    /// Прокладывает крупный список обхода одним заходом.
    private func installBulkBypass(_ nets: [Ipv4Net]) {
        guard !nets.isEmpty else {
            // Список пуст — значит российская зона не прочиталась. Молчать
            // об этом нельзя: весь трафик пойдёт через VPN, и банки
            // с госуслугами увидят казахстанский адрес.
            log.error("Список российской зоны пуст — обход не проложен.")
            message = "Обход российской зоны не работает: переустановите службу."
            return
        }
        guard let via = savedDefaultRoute, !via.gateway.isEmpty else {
            log.error("Не известен шлюз по умолчанию — обход не проложен.")
            message = "Обход российской зоны не работает: переподключитесь."
            return
        }

        let started = Date()
        let outcome = RouteSocket.add(nets, gateway: via.gateway)

        // Запоминаем то, что действительно проложено. Раньше сюда попадал
        // весь список независимо от исхода: состояние врало, а снять потом
        // пытались маршруты, которых не было.
        bulkBypass = outcome.handled > 0 ? Set(nets) : []

        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        log.info("Обход российской зоны: маршрутов \(outcome.handled) из \(nets.count) за \(seconds) с (ошибок \(outcome.failed)).")

        if outcome.handled == 0 {
            log.error("Сокет маршрутизации не принял список — обход не работает.")
            message = "Обход российской зоны не работает: переподключитесь."
        }
    }

    private func removeBulkBypass() {
        guard !bulkBypass.isEmpty, let via = savedDefaultRoute, !via.gateway.isEmpty else {
            bulkBypass = []
            return
        }
        let outcome = RouteSocket.delete(Array(bulkBypass), gateway: via.gateway)
        log.info("Обход снят: маршрутов \(outcome.handled), ошибок \(outcome.failed).")
        bulkBypass = []
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
        // Утилита управления знает туннель по настоящему имени (utunN),
        // а не по нашему «kb0»: по «kb0» она ничего не найдёт.
        guard !realInterfaceName.isEmpty,
              let stats = NetworkTool.peerStats(interface: realInterfaceName) else {
            // Интерфейс исчез (например, его снесли вручную) — поднимаем заново.
            log.error("Туннель недоступен — переподключение.")
            bringDown()
            return
        }

        let now = Date().timeIntervalSince1970

        // Туннель считается поднятым, как только сервер ответил хоть раз.
        // Раньше через три минуты простоя состояние съезжало в «Подключение…»,
        // хотя связь была цела: простаивающий туннель сессию не обновляет,
        // потому что ему нечего слать.
        state = stats.lastHandshake > 0 ? .connected : .connecting

        guard config.options.autoReconnect else { return }

        // Без единого ответа с момента подъёма туннель бесполезен: ключ не
        // от этого сервера, сервер недоступен или сеть режет VPN.
        if stats.lastHandshake == 0 {
            guard now - connectedSince > 40,
                  Date().timeIntervalSince(lastRestartAt) > 60 else { return }
            lastRestartAt = Date()
            log.error("Сервер ни разу не ответил — перезапуск туннеля.")
            message = "Сервер не отвечает, переподключаюсь…"
            bringDown()
            return
        }

        if link.stalled(rx: stats.rxBytes, tx: stats.txBytes, now: now) {
            lastRestartAt = Date()
            log.error("Шлём, а в ответ тишина — перезапуск туннеля.")
            message = "Связь оборвалась, переподключаюсь…"
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
        status.mode = config.effectiveMode
        status.interfaceName = realInterfaceName.isEmpty ? Paths.interfaceName : realInterfaceName
        status.viaBackupEntry = usedBackupEntry
        status.activeMtu = activeMtu
        status.serverName = config.server.name
        status.endpoint = config.server.endpoint
        status.connectedSince = connectedSince
        status.message = message
        status.updatedAt = Date().timeIntervalSince1970

        if isUp, !realInterfaceName.isEmpty,
           let stats = NetworkTool.peerStats(interface: realInterfaceName) {
            status.lastHandshake = stats.lastHandshake
            status.rxBytes = stats.rxBytes
            status.txBytes = stats.txBytes
        }

        switch config.effectiveMode {
        case .full: status.routeCount = 0
        case .include: status.routeCount = tunnelRoutes.count
        case .exclude:
            // Основная часть обхода — российская зона — лежит в bulkBypass,
            // а в bypassRoutes только поштучные правила по IPv6. Считался
            // раньше лишь второй набор, поэтому в окне стоял ноль, хотя
            // тысячи маршрутов были проложены.
            status.routeCount = bulkBypass.count + bypassRoutes.count
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
