import Foundation

/// Что делать, когда служба не находит маршрут по умолчанию.
///
/// Разобрано по журналу службы за трое суток. Картина одна и та же:
/// туннель опускается, и сразу после этого служба часами пишет
/// «Маршрута по умолчанию нет вовсе» — например, 30 сентября с 08:15
/// до 11:38. Интернета нет ни через VPN, ни мимо него. Помогает только
/// человек, который переустанавливает службу: после перезапуска маршрут
/// находится за считаные секунды.
///
/// Причина нашлась в коде лечения. Оно начиналось с проверки «маршрут
/// есть и ведёт в туннель» — и при отсутствии маршрута выходило на
/// первой же строке, ничего не сделав. То есть лечился только тот
/// случай, когда маршрут залип, а самый частый — когда его нет вовсе —
/// не лечился никак. За трое суток в журнале нет ни одной записи
/// о самоперезапуске, хотя повод был часами.
///
/// Теперь решение принимается здесь, по одним и тем же правилам, и его
/// можно проверить, не поднимая туннель.
public enum LostRoute {

    /// Через сколько безуспешных попыток перезапускать службу.
    ///
    /// Попытка идёт примерно раз в семнадцать секунд, так что семь —
    /// это около двух минут. Меньше нельзя: обычное переключение сети
    /// занимает секунды, и дёргать службу из-за него незачем. Больше
    /// незачем: две минуты без интернета человек уже заметил.
    public static let restartAfter = 7

    /// Не чаще этого перезапускаем службу.
    ///
    /// Если интернета нет по-настоящему — выдернули кабель, уехали
    /// из зоны Wi-Fi, — перезапуск не поможет, и долбить им незачем.
    public static let restartPause: TimeInterval = 600

    /// Маршрут по умолчанию, каким его видит система.
    public struct Route: Equatable {
        public let gateway: String
        public let interfaceName: String

        public init(gateway: String, interfaceName: String) {
            self.gateway = gateway
            self.interfaceName = interfaceName
        }
    }

    public enum Action: Equatable {
        /// Ждать: сеть переключается, это нормально.
        case wait

        /// Маршрут ведёт в наш же мёртвый туннель — снять остатки.
        case clearTunnelLeftovers

        /// Проложить маршрут по умолчанию самим, через известный шлюз.
        case restoreVia(Route)

        /// Служба не справляется — перезапустить её.
        case restartService
    }

    /// Годится ли запомненный шлюз для нынешней сети.
    ///
    /// Шлюз запоминается при подъёме туннеля, а человек с ноутбуком
    /// переезжает: из дома в офис, с кабеля на телефон. В журнале это
    /// видно прямо — «Сеть сменилась: en0 192.168.0.1 → en0 192.168.2.1».
    /// Проложить маршрут через шлюз, которого в нынешней сети нет, —
    /// значит сделать хуже, чем было: система не поставит свой, пока
    /// висит наш, и связи не будет вовсе.
    ///
    /// Поэтому шлюз принимается только если он лежит в той же сети,
    /// что и сам интерфейс. Адрес и маску берём у интерфейса сейчас,
    /// а не из памяти.
    public static func gatewayFits(gateway: String, networkOfInterface: Ipv4Net?) -> Bool {
        let clean = gateway.trimmingCharacters(in: .whitespaces)
        // Маршрут без шлюза, прямо в интерфейс, проверять не на что:
        // такой годится, пока сам интерфейс на месте.
        guard !clean.isEmpty else { return true }

        guard let network = networkOfInterface,
              let address = Cidr.parseAddress(clean) else { return false }

        return Int64(address) >= Int64(network.start) && Int64(address) <= network.endInclusive
    }

    /// Решение по одной неудачной попытке.
    ///
    /// - attempts: сколько попыток подряд уже не удалось.
    /// - route: что показывает система сейчас; nil — маршрута нет вовсе.
    /// - ourInterfaces: туннельные интерфейсы, которые служба считает своими.
    /// - lastGoodRoute: физический маршрут, запомненный при подъёме туннеля.
    /// - gatewayStillFits: лежит ли запомненный шлюз в нынешней сети.
    /// - sinceLastRestart: сколько секунд прошло с прошлого самоперезапуска.
    public static func decide(attempts: Int,
                              route: Route?,
                              ourInterfaces: Set<String>,
                              lastGoodRoute: Route?,
                              gatewayStillFits: Bool = true,
                              sinceLastRestart: TimeInterval) -> Action {
        let mayRestart = attempts >= restartAfter && sinceLastRestart >= restartPause

        guard let route else {
            // Маршрута нет вовсе. Это и есть тот случай, который раньше
            // не лечился. Сначала пробуем проложить его сами — это
            // быстрее и незаметнее перезапуска.
            if mayRestart { return .restartService }
            if attempts >= 2, let good = lastGoodRoute, !good.isPhantom, gatewayStillFits {
                return .restoreVia(good)
            }
            return .wait
        }

        // Маршрут есть, но ведёт в туннель — свой или чужой.
        if RouteGuard.isTunnel(interface: route.interfaceName) {
            if ourInterfaces.contains(route.interfaceName) && attempts == 2 {
                return .clearTunnelLeftovers
            }
            if mayRestart { return .restartService }
            return .wait
        }

        // Маршрут есть и он не туннельный: лечить нечего.
        return .wait
    }
}

private extension LostRoute.Route {
    /// Маршрут, которым нельзя воспользоваться: ни шлюза, ни интерфейса.
    var isPhantom: Bool {
        gateway.trimmingCharacters(in: .whitespaces).isEmpty
            && interfaceName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
