import Foundation

/// Считает, что уходит в туннель.
///
/// Логика одна на все платформы: главный фильтр превращается в список
/// адресов, рабочие ресурсы добавляются поверх, российская зона вычитается.
enum RouteBuilder {

    static func routes(for config: AppConfig, profile: WgProfile, bundle: Bundle = .main) async -> [String] {
        let nets = await resolveRules(config)
        let work = await workNets()

        switch config.effectiveMode {
        case .full:
            if config.workFilter || work.isEmpty { return ["0.0.0.0/0"] }
            // Рабочие ресурсы выключены — вычитаем их из полного туннеля.
            return Cidr.complement(work).map(\.text)

        case .include:
            let included = config.workFilter ? nets + work : nets
            if included.isEmpty {
                // Пустой список туннель не примет: оставляем адрес самого клиента.
                let address = profile.addresses.first?.split(separator: "/").first.map(String.init)
                return [address.map { "\($0)/32" } ?? "0.0.0.0/32"]
            }
            return Cidr.merge(included).map(\.text)

        case .exclude:
            let excluded = config.bypassRuZone ? nets + RuZone.networks(bundle: bundle) : nets

            if config.workFilter {
                // Рабочие ресурсы сильнее исключений: возвращаем их в туннель.
                let background = excluded.isEmpty ? [Ipv4Net(start: 0, prefix: 0)] : Cidr.complement(excluded)
                return Cidr.merge(background + work).map(\.text)
            }

            let all = excluded + work
            return all.isEmpty ? ["0.0.0.0/0"] : Cidr.complement(all).map(\.text)
        }
    }

    /// Разворачивает правила в адреса. Когда включён главный фильтр,
    /// к правилам добавляется встроенный список сервисов.
    private static func resolveRules(_ config: AppConfig) async -> [Ipv4Net] {
        var result: [Ipv4Net] = []
        var domains: [String] = []

        for rule in config.activeRules {
            switch rule.kind {
            case .cidr:
                if let net = Cidr.parse(rule.value) { result.append(net) }
            case .domain:
                domains.append(rule.value.trimmingCharacters(in: .whitespaces).lowercased())
            }
        }

        if config.mainFilter {
            domains += MasterFilter.domains
        }

        if !domains.isEmpty {
            result += await DomainResolver.resolveAll(domains)
        }

        var seen = Set<Ipv4Net>()
        return result.filter { seen.insert($0).inserted }
    }

    /// Адреса рабочих ресурсов: заложенные в приложение узлы.
    private static func workNets() async -> [Ipv4Net] {
        var result: [Ipv4Net] = []
        var domains: [String] = []

        for host in WorkFilter.hosts {
            if let net = Cidr.parse(host) { result.append(net) }
            else { domains.append(host.lowercased()) }
        }

        if !domains.isEmpty {
            result += await DomainResolver.resolveAll(domains)
        }

        var seen = Set<Ipv4Net>()
        return result.filter { seen.insert($0).inserted }
    }
}
