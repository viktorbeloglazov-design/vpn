import Foundation

struct IPInfo {
    var ip: String
    var country: String
    var city: String
    var org: String

    var isKazakhstan: Bool { country.uppercased() == "KZ" }

    var summary: String {
        var parts: [String] = [ip]
        if !country.isEmpty {
            let flagged = country.uppercased() == "KZ" ? "🇰🇿 KZ" : country.uppercased()
            parts.append(city.isEmpty ? flagged : "\(flagged), \(city)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Проверка внешнего IP — так видно, что трафик действительно выходит из Казахстана.
enum IPCheck {

    static func fetch(completion: @escaping (Result<IPInfo, Error>) -> Void) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)

        guard let url = URL(string: "https://ipinfo.io/json") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        session.dataTask(with: url) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ip = json["ip"] as? String else {
                DispatchQueue.main.async { completion(.failure(URLError(.cannotParseResponse))) }
                return
            }
            let info = IPInfo(ip: ip,
                              country: (json["country"] as? String) ?? "",
                              city: (json["city"] as? String) ?? "",
                              org: (json["org"] as? String) ?? "")
            DispatchQueue.main.async { completion(.success(info)) }
        }.resume()
    }
}
