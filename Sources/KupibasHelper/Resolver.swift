import Foundation

enum Resolver {

    /// Резолвит домен в список IP-адресов (A и AAAA).
    static func resolve(_ host: String) -> [String] {
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
