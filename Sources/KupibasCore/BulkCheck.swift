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

    /// Чем кончилась проверка.
    public enum Verdict: Sendable {
        /// Большие порции проходят — размер пакета подходит.
        case passes

        /// Соединение есть, данные не идут — размер пакета великоват.
        case stalls

        /// Проверить не вышло: ни один источник не отозвался.
        ///
        /// Раньше этот случай считался успехом — «раз не проверили, значит
        /// всё хорошо». Из-за этого оставался размер из ключа, а человек
        /// потом не мог скачать ни фото, ни видео. Неизвестность — это
        /// неизвестность, и размер берётся заведомо проходимый.
        case unknown
    }

    public static func check() -> Verdict {
        for source in sources {
            switch download(source) {
            case .ok: return .passes
            case .stalled: return .stalls
            case .unreachable: continue
            }
        }
        return .unknown
    }

    /// Проходят ли большие порции. false — размер пакета стоит уменьшить.
    ///
    /// Оставлено для тех мест, где важен только ответ «да или нет».
    /// Непроверенное считается непроходящим: лучше пакет поменьше,
    /// чем связь, которой нельзя пользоваться.
    public static func works() -> Bool {
        if case .passes = check() { return true }
        return false
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
