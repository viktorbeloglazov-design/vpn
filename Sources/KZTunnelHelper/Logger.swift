import Foundation

final class Logger {
    private let path: String
    private let queue = DispatchQueue(label: "kztunnel.logger")
    private let maxSize = 2 * 1024 * 1024
    private let formatter: DateFormatter

    init(path: String) {
        self.path = path
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.formatter = formatter
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path,
                                           contents: nil,
                                           attributes: [.posixPermissions: NSNumber(value: Int16(0o644))])
        }
    }

    func info(_ message: String) { write("INFO", message) }
    func error(_ message: String) { write("ERROR", message) }

    private func write(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        queue.async { [path, maxSize] in
            FileHandle.standardError.write(Data(line.utf8))
            guard let handle = FileHandle(forWritingAtPath: path) else { return }
            defer { try? handle.close() }
            if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int,
               size > maxSize {
                try? handle.truncate(atOffset: 0)
            }
            _ = try? handle.seekToEnd()
            handle.write(Data(line.utf8))
        }
    }
}
