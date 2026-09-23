import Foundation

/// Проверка, годится ли найденный маршрут по умолчанию.
///
/// Служба запоминает его при подъёме туннеля: через этот шлюз потом идёт
/// весь обход — российская зона, адрес самого сервера. Если запомнить
/// маршрут, ведущий в туннель, обход проложится в никуда: связь пропадёт
/// целиком и не вернётся, пока службу не перезапустят.
///
/// Так и случалось при переподключении. Туннель опускали и тут же поднимали
/// заново — система ещё не успевала вернуть прежний маршрут, и служба
/// читала свой собственный, уже мёртвый интерфейс.
public enum RouteGuard {

    /// Имена, с которых начинаются туннельные интерфейсы macOS.
    private static let tunnelPrefixes = ["utun", "ipsec", "gif", "stf", "ppp"]

    /// Туннельный ли это интерфейс — наш или чужого VPN.
    public static func isTunnel(interface name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !clean.isEmpty else { return false }
        return tunnelPrefixes.contains { clean.hasPrefix($0) }
    }

    /// Годится ли маршрут как «дорога в обход туннеля».
    ///
    /// Нужен шлюз или интерфейс, и этот интерфейс не должен быть туннельным.
    public static func isUsable(gateway: String, interface: String) -> Bool {
        let hasWay = !gateway.trimmingCharacters(in: .whitespaces).isEmpty
            || !interface.trimmingCharacters(in: .whitespaces).isEmpty
        return hasWay && !isTunnel(interface: interface)
    }
}
