import Compression
import Foundation

/// Разбор того, чем делится Amnezia.
///
/// Кнопка «Поделиться» отдаёт ссылку `vpn://…` и QR-код с ней же. Внутри —
/// сжатый свёрток с настройками, где лежит обычный текст конфигурации
/// WireGuard или AmneziaWG. Здесь свёрток разворачивается обратно в этот текст.
///
/// Понимает и простые случаи: сам файл .conf, голый base64, несжатый JSON.
public enum SharedLink {

    private static let marker = "[Interface]"

    /// Достаёт текст конфигурации из чего угодно, чем поделились.
    public static func extractConfig(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text.contains(marker) { return cleanUp(text) }

        var payload = text
        for prefix in ["vpn://", "VPN://", "amnezia://"] where payload.hasPrefix(prefix) {
            payload = String(payload.dropFirst(prefix.count))
        }
        payload = payload.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let bytes = decodeBase64(payload) else { return nil }

        // Qt кладёт впереди четыре байта с исходным размером, дальше zlib.
        let expected = expectedSize(bytes)
        for skip in [4, 6, 0, 2] where bytes.count > skip {
            guard let unpacked = inflate(bytes.dropFirst(skip), expected: expected) else { continue }
            if let config = fromText(unpacked) { return config }
        }
        if let plain = String(data: bytes, encoding: .utf8) { return fromText(plain) }
        return nil
    }

    /// Похоже ли это на ссылку, которой делятся, а не на случайный текст.
    public static func looksLikeLink(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.hasPrefix("vpn://") || text.hasPrefix("amnezia://")
    }

    // MARK: - Внутреннее

    /// В свёртке Amnezia настройки лежат в поле вложенного JSON, и структура
    /// от версии к версии меняется. Поэтому ищем не по именам полей, а по
    /// самому признаку конфигурации — строке «[Interface]».
    private static func fromText(_ text: String) -> String? {
        guard let start = text.range(of: marker) else { return nil }
        if !text.contains("\"") { return cleanUp(text) }

        let head = text[text.startIndex..<start.lowerBound]
        guard let quoteBefore = head.lastIndex(of: "\"") else { return cleanUp(text) }
        guard let quoteAfter = closingQuote(in: text, from: start.lowerBound) else { return cleanUp(text) }

        let raw = String(text[text.index(after: quoteBefore)..<quoteAfter])
        return cleanUp(unescapeJson(raw))
    }

    private static func closingQuote(in text: String, from: String.Index) -> String.Index? {
        var index = from
        var previous: Character = " "
        while index < text.endIndex {
            if text[index] == "\"" && previous != "\\" { return index }
            previous = text[index]
            index = text.index(after: index)
        }
        return nil
    }

    private static func unescapeJson(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Обрезает всё, что оказалось до и после самой конфигурации.
    private static func cleanUp(_ text: String) -> String {
        guard let start = text.range(of: marker) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let body = text[start.lowerBound...]
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).prefix { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.hasPrefix("[") || trimmed.hasPrefix("#") || trimmed.contains("=")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeBase64(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .filter { !$0.isWhitespace }
        switch normalized.count % 4 {
        case 2: normalized += "=="
        case 3: normalized += "="
        case 0: break
        default: return nil
        }
        return Data(base64Encoded: normalized)
    }

    /// Первые четыре байта свёртка — размер распакованных данных.
    private static func expectedSize(_ bytes: Data) -> Int {
        guard bytes.count > 4 else { return 0 }
        let head = [UInt8](bytes.prefix(4))
        let size = (Int(head[0]) << 24) | (Int(head[1]) << 16) | (Int(head[2]) << 8) | Int(head[3])
        return size > 0 && size < 8 * 1024 * 1024 ? size : 0
    }

    /// Распаковка потока deflate без заголовка zlib.
    private static func inflate<T: DataProtocol>(_ input: T, expected: Int) -> String? {
        let data = Data(input)
        if data.isEmpty { return nil }

        let capacity = max(expected + 1024, 512 * 1024)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let target = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { source -> Int in
                guard let origin = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(target, capacity, origin, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return String(data: output.prefix(written), encoding: .utf8)
    }
}
