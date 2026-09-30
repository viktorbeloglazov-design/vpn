import Foundation
import KupibasCore

enum Resolver {

    /// Сколько ждём ответа от DNS.
    ///
    /// Системный запрос имени сам по себе не торопится: когда DNS
    /// не отвечает, он перебирает серверы и попытки и возвращается
    /// через полминуты, а то и позже. Служба спрашивает имена из
    /// своего единственного цикла, и всё это время цикл стоит:
    /// туннель не поддерживается, состояние не публикуется.
    ///
    /// Поэтому ждём столько, сколько не жалко, и идём дальше.
    /// Незавершённый запрос остаётся в своём потоке и никому
    /// не мешает — его ответ просто никому не нужен.
    static let timeout: TimeInterval = 5

    /// Кому рассказывать, что сейчас спрашиваем имя.
    static var watchdog: Watchdog?

    /// Резолвит домен в список IP-адресов (A и AAAA).
    ///
    /// Не ждёт дольше `timeout`: молчащий DNS не должен останавливать
    /// службу.
    static func resolve(_ host: String) -> [String] {
        watchdog?.begin("узнаю адрес \(host)", now: Date().timeIntervalSince1970)
        defer { watchdog?.end(now: Date().timeIntervalSince1970) }

        let done = DispatchSemaphore(value: 0)
        let box = Answer()

        Thread {
            let addresses = lookup(host)
            box.put(addresses)
            done.signal()
        }.start()

        guard done.wait(timeout: .now() + timeout) == .success else { return [] }
        return box.take()
    }

    /// Ответ, который пишет один поток, а забирает другой.
    private final class Answer {
        private let lock = NSLock()
        private var addresses: [String] = []

        func put(_ value: [String]) {
            lock.lock(); defer { lock.unlock() }
            addresses = value
        }

        func take() -> [String] {
            lock.lock(); defer { lock.unlock() }
            return addresses
        }
    }

    /// Сам запрос к системе. Возвращается когда вернётся.
    private static func lookup(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0, let head = result else { return [] }
        defer { freeaddrinfo(head) }

        var addresses: [String] = []
        var node: UnsafeMutablePointer<addrinfo>? = head
        while let current = node {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let code = getnameinfo(current.pointee.ai_addr,
                                   socklen_t(current.pointee.ai_addrlen),
                                   &buffer,
                                   socklen_t(buffer.count),
                                   nil,
                                   0,
                                   NI_NUMERICHOST)
            if code == 0 {
                var address = String(cString: buffer)
                // Убираем зону вида fe80::1%en0 — такие адреса нам не нужны.
                if let percent = address.firstIndex(of: "%") {
                    address = String(address[address.startIndex..<percent])
                }
                if isRoutable(address) && !addresses.contains(address) {
                    addresses.append(address)
                }
            }
            node = current.pointee.ai_next
        }
        return addresses
    }

    /// Отсекаем loopback, link-local и «пустые» ответы DNS-заглушек.
    private static func isRoutable(_ address: String) -> Bool {
        if address.isEmpty { return false }
        if address == "::1" || address == "::" { return false }
        if address.lowercased().hasPrefix("fe80:") { return false }
        if address.hasPrefix("127.") { return false }
        if address.hasPrefix("169.254.") { return false }
        if address == "0.0.0.0" { return false }
        return true
    }
}
