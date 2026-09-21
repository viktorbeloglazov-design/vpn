import Foundation

/// Проверка, что через туннель проходят большие порции данных.
///
/// Слишком большой пакет — самая частая причина жалоб вида «сообщения
/// отправляются, а видео крутится и не скачивается». Мелкие пакеты
/// пролезают, крупные сеть не пропускает целиком, и каждая порция уходит
/// заново: связь вроде есть, а толку нет.
///
/// Отличить это от просто медленной сети помогает порядок величин: даже на
/// плохом канале сотня килобайт приходит за несколько секунд, а при
/// неподходящем размере пакета не приходит вовсе.
public enum BulkCheck {

    /// Столько байт достаточно, чтобы задеть проблему с размером пакета.
    private static let needed = 128 * 1024
    private static let timeout: TimeInterval = 9

    private static let sources = [
        "https://speed.cloudflare.com/__down?bytes=1000000",
        "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png",
        "https://raw.githubusercontent.com/viktorbeloglazov-design/vpn/main/README.md",
    ]

    private enum Outcome { case ok, stalled, unreachable }

    /// Проходят ли большие порции. false — размер пакета стоит уменьшить.
    public static func works() -> Bool {
        for source in sources {
            switch download(source) {
            case .ok: return true
            case .stalled: return false
            case .unreachable: continue
            }
        }
        // Ни один источник не отозвался: проблема не в размере пакета,
        // и уменьшать его вслепую незачем.
        return true
    }

    private static func download(_ text: String) -> Outcome {
        guard let url = URL(string: text) else { return .unreachable }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let session = URLSession(configuration: .ephemeral)
        var outcome = Outcome.unreachable
        let done = DispatchSemaphore(value: 0)

        let task = session.dataTask(with: request) { data, response, error in
            defer { done.signal() }

            if let error = error as NSError?, error.code == NSURLErrorTimedOut {
                // Соединение установилось, а данные не идут — это как раз оно.
                outcome = .stalled
                return
            }
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data
            else { return }

            let expected = http.expectedContentLength
            // Файл кончился раньше — значит, он просто небольшой и дошёл целиком.
            outcome = (data.count >= needed || (expected > 0 && Int64(data.count) >= expected))
                ? .ok
                : .stalled
        }
        task.resume()

        if done.wait(timeout: .now() + timeout + 3) == .timedOut {
            task.cancel()
            return .stalled
        }
        return outcome
    }
}
