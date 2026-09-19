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

    // MARK: - Внутреннее

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
