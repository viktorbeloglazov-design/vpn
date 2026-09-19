import Foundation

/// Превращает домены в адреса.
///
/// Внутри России обычный DNS нередко отвечает подставными адресами, поэтому
/// сначала спрашиваем через DNS-over-HTTPS и только потом — системный
/// резолвер. Домены разбираются пачками: двести с лишним имён по очереди
/// складываются в минуты ожидания.
enum DomainResolver {

    private static let parallel = 16

    private static let dohEndpoints = [
        "https://dns.google/resolve",
        "https://cloudflare-dns.com/dns-query",
    ]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private static let cacheQueue = DispatchQueue(label: "kz.qpvpn.resolver.cache")
    private static var cache: [String: [Ipv4Net]] = [:]

    static func clearCache() {
        cacheQueue.sync { cache = [:] }
    }

    static func resolveAll(_ hosts: [String], useSecureDns: Bool = true) async -> [Ipv4Net] {
        var seen = Set<String>()
        let unique = hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }

        var result: [Ipv4Net] = []
        var index = 0

        while index < unique.count {
            let slice = Array(unique[index..<min(index + parallel, unique.count)])
            index += slice.count

            await withTaskGroup(of: [Ipv4Net].self) { group in
                for host in slice {
                    group.addTask { await resolve(host, useSecureDns: useSecureDns) }
                }
                for await nets in group {
                    result += nets
                }
            }
        }

        var unique_nets = Set<Ipv4Net>()
        return result.filter { unique_nets.insert($0).inserted }
    }

    private static func resolve(_ host: String, useSecureDns: Bool) async -> [Ipv4Net] {
        if let cached = cacheQueue.sync(execute: { cache[host] }) { return cached }

        var nets: [Ipv4Net] = []
        if useSecureDns {
            nets = await resolveOverHttps(host)
        }
        if nets.isEmpty {
            nets = resolveOverSystem(host)
        }

        if !nets.isEmpty {
            cacheQueue.sync { cache[host] = nets }
        }
        return nets
    }

    private static func resolveOverHttps(_ host: String) async -> [Ipv4Net] {
        for endpoint in dohEndpoints {
            guard var components = URLComponents(string: endpoint) else { continue }
            components.queryItems = [
                URLQueryItem(name: "name", value: host),
                URLQueryItem(name: "type", value: "A"),
            ]
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.setValue("application/dns-json", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let answers = json["Answer"] as? [[String: Any]]
            else { continue }

            let nets = answers.compactMap { answer -> Ipv4Net? in
                guard (answer["type"] as? Int) == 1, let data = answer["data"] as? String else { return nil }
                return Cidr.parse(data)
            }
            if !nets.isEmpty { return nets }
        }
        return []
    }

    /// Запасной путь: системный резолвер телефона.
    private static func resolveOverSystem(_ host: String) -> [Ipv4Net] {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &info) == 0, let first = info else { return [] }
        defer { freeaddrinfo(info) }

        var nets: [Ipv4Net] = []
        var pointer: UnsafeMutablePointer<addrinfo>? = first
        while let current = pointer {
            if current.pointee.ai_family == AF_INET, let address = current.pointee.ai_addr {
                address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { socket in
                    let value = UInt32(bigEndian: socket.pointee.sin_addr.s_addr)
                    nets.append(Ipv4Net(start: value, prefix: 32))
                }
            }
            pointer = current.pointee.ai_next
        }
        return nets
    }
}
