import Foundation

/// Подсеть IPv4: адрес начала и длина префикса.
public struct Ipv4Net: Hashable, Sendable {
    public let start: UInt32
    public let prefix: Int

    public init(start: UInt32, prefix: Int) {
        self.start = start
        self.prefix = prefix
    }

    public var size: Int64 { Int64(1) << (32 - prefix) }
    public var endInclusive: Int64 { Int64(start) + size - 1 }

    public var text: String {
        let a = (start >> 24) & 0xFF
        let b = (start >> 16) & 0xFF
        let c = (start >> 8) & 0xFF
        let d = start & 0xFF
        return "\(a).\(b).\(c).\(d)/\(prefix)"
    }
}

/// Разбор адресов и арифметика подсетей.
///
/// Туннелю задаётся список того, что в него заходит. Поэтому режим
/// «всё кроме правил» считается как дополнение — всё адресное пространство
/// минус исключённые подсети.
public enum Cidr {

    public static func parseAddress(_ value: String) -> UInt32? {
        let parts = value.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var result: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber) else { return nil }
            if part.count > 1 && part.first == "0" { return nil }
            guard let number = UInt32(part), number <= 255 else { return nil }
            result = (result << 8) | number
        }
        return result
    }

    /// Принимает «10.0.0.0/8» и одиночный «1.2.3.4» (станет /32).
    public static func parse(_ value: String) -> Ipv4Net? {
        let text = value.trimmingCharacters(in: .whitespaces)
        guard let slash = text.firstIndex(of: "/") else {
            guard let address = parseAddress(text) else { return nil }
            return Ipv4Net(start: address, prefix: 32)
        }

        guard let address = parseAddress(String(text[text.startIndex..<slash])),
              let prefix = Int(text[text.index(after: slash)...]),
              (0...32).contains(prefix)
        else { return nil }

        let mask: UInt32 = prefix == 0 ? 0 : ~((1 << (32 - UInt32(prefix))) - 1)
        return Ipv4Net(start: address & mask, prefix: prefix)
    }

    public static func isDomain(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty, text.count <= 253, text.contains(".") else { return false }
        guard !text.hasPrefix("."), !text.hasSuffix("."), !text.contains("..") else { return false }
        guard text.allSatisfy({ ($0.isLetter || $0.isNumber) && $0.isASCII || $0 == "." || $0 == "-" }) else { return false }
        return text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
        }
    }

    /// Схлопывает пересекающиеся и соседние подсети.
    public static func merge(_ nets: [Ipv4Net]) -> [Ipv4Net] {
        guard !nets.isEmpty else { return [] }
        let ranges = nets.map { (Int64($0.start), $0.endInclusive) }.sorted { $0.0 < $1.0 }

        var merged: [(Int64, Int64)] = []
        for range in ranges {
            if let last = merged.last, range.0 <= last.1 + 1 {
                merged[merged.count - 1] = (last.0, max(last.1, range.1))
            } else {
                merged.append(range)
            }
        }
        return merged.flatMap { rangeToNets(from: $0.0, to: $0.1) }
    }

    /// Всё адресное пространство минус перечисленные подсети.
    public static func complement(_ excluded: [Ipv4Net]) -> [Ipv4Net] {
        guard !excluded.isEmpty else { return [Ipv4Net(start: 0, prefix: 0)] }
        let ranges = excluded.map { (Int64($0.start), $0.endInclusive) }.sorted { $0.0 < $1.0 }

        var merged: [(Int64, Int64)] = []
        for range in ranges {
            if let last = merged.last, range.0 <= last.1 + 1 {
                merged[merged.count - 1] = (last.0, max(last.1, range.1))
            } else {
                merged.append(range)
            }
        }

        var result: [Ipv4Net] = []
        var cursor: Int64 = 0
        for (start, end) in merged {
            if start > cursor {
                result += rangeToNets(from: cursor, to: start - 1)
            }
            cursor = max(cursor, end + 1)
            if cursor > 0xFFFF_FFFF { break }
        }
        if cursor <= 0xFFFF_FFFF {
            result += rangeToNets(from: cursor, to: 0xFFFF_FFFF)
        }
        return result
    }

    /// Вычитает одни подсети из других: «эти адреса — кроме вот этих».
    ///
    /// Нужно для рабочих ресурсов: их адрес лежит в российской зоне, но
    /// уходить мимо туннеля он не должен.
    public static func subtract(_ nets: [Ipv4Net], _ removed: [Ipv4Net]) -> [Ipv4Net] {
        guard !removed.isEmpty else { return merge(nets) }

        let holes = merge(removed).map { (Int64($0.start), $0.endInclusive) }
        var result: [Ipv4Net] = []

        for net in merge(nets) {
            var pieces: [(Int64, Int64)] = [(Int64(net.start), net.endInclusive)]
            for hole in holes {
                var next: [(Int64, Int64)] = []
                for piece in pieces {
                    if hole.1 < piece.0 || hole.0 > piece.1 {
                        next.append(piece)
                        continue
                    }
                    if hole.0 > piece.0 { next.append((piece.0, hole.0 - 1)) }
                    if hole.1 < piece.1 { next.append((hole.1 + 1, piece.1)) }
                }
                pieces = next
                if pieces.isEmpty { break }
            }
            for piece in pieces {
                result += rangeToNets(from: piece.0, to: piece.1)
            }
        }
        return result
    }

    /// Наименьший набор подсетей, покрывающий диапазон адресов целиком.
    public static func rangeToNets(from start: Int64, to endInclusive: Int64) -> [Ipv4Net] {
        var result: [Ipv4Net] = []
        var current = start
        while current <= endInclusive {
            var prefix = 32
            while prefix > 0 {
                let candidate = prefix - 1
                let size = Int64(1) << (32 - candidate)
                if current % size != 0 || current + size - 1 > endInclusive { break }
                prefix = candidate
            }
            result.append(Ipv4Net(start: UInt32(current), prefix: prefix))
            current += Int64(1) << (32 - prefix)
        }
        return result
    }
}
