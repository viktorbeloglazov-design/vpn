import Foundation

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { status == 0 }

    /// Короткое описание ошибки для показа в интерфейсе.
    var failureText: String {
        let text = (stderr.isEmpty ? stdout : stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "код выхода \(status)" : text
    }
}

enum Shell {
    /// Homebrew-каталоги идут первыми: wg-quick и wireguard-go живут там.
    static let searchPaths = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin",
        "/usr/local/bin", "/usr/local/sbin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]

    static var pathEnvironment: String { searchPaths.joined(separator: ":") }

    static func which(_ name: String) -> String? {
        for directory in searchPaths {
            let path = directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 90) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = pathEnvironment
        environment["LANG"] = "C"
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: "не удалось запустить \(executable): \(error.localizedDescription)")
        }

        // Читаем оба потока параллельно, иначе длинный вывод в stderr заблокирует процесс.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "kupibas.shell.read", attributes: .concurrent)
        queue.async(group: group) { outData = outPipe.fileHandleForReading.readDataToEndOfFile() }
        queue.async(group: group) { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            usleep(200_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        _ = group.wait(timeout: .now() + 5)

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Запуск утилиты по имени с поиском в PATH.
    @discardableResult
    static func runTool(_ name: String, _ arguments: [String], timeout: TimeInterval = 90) -> CommandResult {
        guard let path = which(name) else {
            return CommandResult(status: -1, stdout: "", stderr: "утилита \(name) не найдена")
        }
        return run(path, arguments, timeout: timeout)
    }
}
