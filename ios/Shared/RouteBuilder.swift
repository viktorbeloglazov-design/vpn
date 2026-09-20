import Foundation

/// Считает, что уходит в туннель.
///
/// Логика одна на все платформы и не настраивается: через VPN идёт всё,
/// кроме российской зоны, а рабочие ресурсы возвращаются в туннель поверх
/// неё — если человек не выключил их единственным переключателем.
enum RouteBuilder {

    /// Столько маршрутов система принимает спокойно.
    private static let maxRoutes = 4_000

    /// Шаги укрупнения: насколько большой промежуток между подсетями прощаем.
    private static let gaps: [Int64] = [4_096, 16_384, 65_536, 262_144, 1_048_576]

    static func routes(for config: AppConfig, profile: WgProfile, bundle: Bundle = .main) async -> [String] {
        let work = await workNets()

        // Маршрутизация зашита: через VPN идёт всё, кроме российской зоны.
        // Так заблокированный сервис открывается, даже если его адрес
        // программе незнаком, а банки и госуслуги работают напрямую.
        let zone = fittingRuZone(bundle: bundle)

        if config.workFilter {
            // Рабочие ресурсы сильнее исключений: возвращаем их в туннель,
            // даже если они попали в российскую зону.
            let background = zone.isEmpty ? [Ipv4Net(start: 0, prefix: 0)] : Cidr.complement(zone)
            return Cidr.merge(background + work).map(\.text)
        }

        let all = zone + work
        return all.isEmpty ? ["0.0.0.0/0"] : Cidr.complement(all).map(\.text)
    }

    /// Российская зона, ужатая до размера, который система принимает.
    ///
    /// Точный список даёт больше двадцати тысяч маршрутов: столько система
    /// принимает долго, и туннель поднимается заметными секундами. Список
    /// укрупняется, пока маршрутов не станет разумное количество, а сервисы,
    /// которые при этом могли бы уйти мимо туннеля, возвращаются обратно.
    private static func fittingRuZone(bundle: Bundle) -> [Ipv4Net] {
        if let cached = cachedZone { return cached }

        let exact = RuZone.networks(bundle: bundle)
        guard !exact.isEmpty else { return [] }

        let keep = KeepInTunnel.nets()
        var zone = Cidr.subtract(exact, keep)
        var routes = Cidr.complement(zone).count
        var step = 0

        while routes > maxRoutes && step < gaps.count {
            zone = Cidr.subtract(Cidr.mergeWithGap(exact, gap: gaps[step]), keep)
            routes = Cidr.complement(zone).count
            step += 1
        }

        cachedZone = zone
        return zone
    }

    /// Считается один раз за запуск: файл не меняется.
    private static var cachedZone: [Ipv4Net]?

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
