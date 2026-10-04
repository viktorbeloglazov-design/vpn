import Darwin
import Foundation
import KupibasCore

/// Пакетная работа с таблицей маршрутов.
///
/// Обход российской зоны — это 8 649 подсетей. Вызывать для каждой
/// /sbin/route означало бы восемь с половиной тысяч запусков программы:
/// минута ожидания на включении и столько же на выключении. Поэтому
/// маршруты пишутся напрямую в сокет маршрутизации, как это делает сама
/// система: весь список уходит за доли секунды.
enum RouteSocket {

    struct Outcome {
        var added = 0
        var existed = 0
        var failed = 0

        init(added: Int = 0, existed: Int = 0, failed: Int = 0) {
            self.added = added
            self.existed = existed
            self.failed = failed
        }

        var handled: Int { added + existed }
    }

    /// Прокладывает маршруты в обход туннеля — через физический шлюз.
    static func add(_ nets: [Ipv4Net], gateway: String) -> Outcome {
        send(nets, gateway: gateway, type: RTM_ADD)
    }

    /// Убирает ранее проложенные маршруты.
    static func delete(_ nets: [Ipv4Net], gateway: String) -> Outcome {
        send(nets, gateway: gateway, type: RTM_DELETE)
    }

    /// Прокладывает маршруты в туннель — прямо в интерфейс, без шлюза.
    ///
    /// То же, что `route add -net X -interface utunN`, только всё одним
    /// сокетом. Раньше на каждый маршрут запускалась отдельная программа:
    /// полторы сотни маршрутов нового режима — полминуты на включении
    /// и столько же на выключении. Всё это время служба молчала, и
    /// приложение писало «служба не отвечает».
    ///
    /// Возвращает подсети, которые записать не вышло: их вызывающий
    /// прокладывает по-старому, программой.
    static func addToInterface(_ nets: [Ipv4Net], interfaceName: String) -> (outcome: Outcome, failed: [Ipv4Net]) {
        let index = if_nametoindex(interfaceName)
        guard index > 0 else { return (Outcome(failed: nets.count), nets) }
        var link = sockaddr_dl()
        link.sdl_len = UInt8(MemoryLayout<sockaddr_dl>.size)
        link.sdl_family = sa_family_t(AF_LINK)
        link.sdl_index = UInt16(index)
        let gateway = withUnsafeBytes(of: &link) { Data($0) }
        return sendEach(nets, type: RTM_ADD, flags: RTF_UP | RTF_STATIC, gateway: gateway)
    }

    /// Убирает маршруты по адресу и маске, куда бы они ни вели.
    ///
    /// То же, что `route delete -net X`. Возвращает подсети, которые
    /// убрать не вышло.
    static func deleteNets(_ nets: [Ipv4Net]) -> (outcome: Outcome, failed: [Ipv4Net]) {
        sendEach(nets, type: RTM_DELETE, flags: RTF_UP | RTF_STATIC, gateway: nil)
    }

    // MARK: - Внутреннее

    /// Шлёт по сообщению на подсеть и запоминает, какие не прошли.
    private static func sendEach(_ nets: [Ipv4Net], type: Int32, flags: Int32,
                                 gateway: Data?) -> (outcome: Outcome, failed: [Ipv4Net]) {
        var outcome = Outcome()
        var failed: [Ipv4Net] = []
        guard !nets.isEmpty else { return (outcome, failed) }

        let descriptor = socket(PF_ROUTE, SOCK_RAW, AF_INET)
        guard descriptor >= 0 else { return (Outcome(failed: nets.count), nets) }
        defer { close(descriptor) }

        var off: Int32 = 0
        setsockopt(descriptor, SOL_SOCKET, SO_USELOOPBACK, &off, socklen_t(MemoryLayout<Int32>.size))

        var sequence: Int32 = 1
        for net in nets {
            var message = self.message(type: type, flags: flags, sequence: sequence,
                                       net: net, gateway: gateway)
            sequence += 1

            let written = message.withUnsafeMutableBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return write(descriptor, base, buffer.count)
            }

            if written > 0 {
                outcome.added += 1
            } else if errno == EEXIST || (type == RTM_DELETE && errno == ESRCH) {
                outcome.existed += 1
            } else {
                outcome.failed += 1
                failed.append(net)
            }
        }
        return (outcome, failed)
    }

    /// Сообщение с произвольным шлюзом: адресом, интерфейсом или без него.
    private static func message(type: Int32, flags: Int32, sequence: Int32,
                                net: Ipv4Net, gateway: Data?) -> Data {
        let headerSize = MemoryLayout<rt_msghdr>.size
        let addressSize = MemoryLayout<sockaddr_in>.size

        var header = rt_msghdr()
        header.rtm_msglen = UInt16(headerSize + 2 * addressSize + (gateway?.count ?? 0))
        header.rtm_version = UInt8(RTM_VERSION)
        header.rtm_type = UInt8(type)
        header.rtm_index = 0
        header.rtm_flags = flags
        header.rtm_addrs = RTA_DST | RTA_NETMASK | (gateway == nil ? 0 : RTA_GATEWAY)
        header.rtm_pid = 0
        header.rtm_seq = sequence
        header.rtm_errno = 0

        let mask: UInt32 = net.prefix == 0 ? 0 : ~((UInt32(1) << (32 - UInt32(net.prefix))) - 1)
        var destination = socketAddress(net.start.bigEndian)
        var netmask = socketAddress(mask.bigEndian)

        // Порядок адресов в сообщении задан ядром: адрес, шлюз, маска.
        var data = Data()
        withUnsafeBytes(of: &header) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &destination) { data.append(contentsOf: $0) }
        if let gateway { data.append(gateway) }
        withUnsafeBytes(of: &netmask) { data.append(contentsOf: $0) }
        return data
    }

    private static func send(_ nets: [Ipv4Net], gateway: String, type: Int32) -> Outcome {
        var outcome = Outcome()
        guard !nets.isEmpty else { return outcome }

        let gatewayAddress = inet_addr(gateway)
        guard gatewayAddress != INADDR_NONE else {
            outcome.failed = nets.count
            return outcome
        }

        let descriptor = socket(PF_ROUTE, SOCK_RAW, AF_INET)
        guard descriptor >= 0 else {
            outcome.failed = nets.count
            return outcome
        }
        defer { close(descriptor) }

        // Ответы ядра нам не нужны — иначе очередь чтения переполнится
        // на тысячах сообщений.
        var off: Int32 = 0
        setsockopt(descriptor, SOL_SOCKET, SO_USELOOPBACK, &off, socklen_t(MemoryLayout<Int32>.size))

        var sequence: Int32 = 1
        for net in nets {
            var message = self.message(type: type, sequence: sequence, net: net, gateway: gatewayAddress)
            sequence += 1

            let written = message.withUnsafeMutableBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return write(descriptor, base, buffer.count)
            }

            if written > 0 {
                outcome.added += 1
            } else if errno == EEXIST || errno == ESRCH {
                // Маршрут уже есть (или его уже нет) — это не ошибка.
                outcome.existed += 1
            } else {
                outcome.failed += 1
            }
        }
        return outcome
    }

    private static func message(type: Int32, sequence: Int32, net: Ipv4Net, gateway: in_addr_t) -> Data {
        let headerSize = MemoryLayout<rt_msghdr>.size
        let addressSize = MemoryLayout<sockaddr_in>.size

        var header = rt_msghdr()
        header.rtm_msglen = UInt16(headerSize + 3 * addressSize)
        header.rtm_version = UInt8(RTM_VERSION)
        header.rtm_type = UInt8(type)
        header.rtm_index = 0
        header.rtm_flags = RTF_UP | RTF_GATEWAY | RTF_STATIC
        header.rtm_addrs = RTA_DST | RTA_GATEWAY | RTA_NETMASK
        header.rtm_pid = 0
        header.rtm_seq = sequence
        header.rtm_errno = 0

        let mask: UInt32 = net.prefix == 0 ? 0 : ~((UInt32(1) << (32 - UInt32(net.prefix))) - 1)

        var destination = socketAddress(net.start.bigEndian)
        var via = socketAddress(gateway)
        var netmask = socketAddress(mask.bigEndian)

        var data = Data()
        withUnsafeBytes(of: &header) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &destination) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &via) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &netmask) { data.append(contentsOf: $0) }
        return data
    }

    private static func socketAddress(_ value: in_addr_t) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: value)
        return address
    }
}
