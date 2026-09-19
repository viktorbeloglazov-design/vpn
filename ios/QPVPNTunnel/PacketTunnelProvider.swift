import Foundation
import NetworkExtension
import WireGuardKit
import os

/// Расширение, которое и есть туннель.
///
/// Приложение кладёт в системный профиль готовый текст настроек с уже
/// посчитанными маршрутами, а здесь он превращается в работающий туннель
/// силами библиотеки AmneziaWG.
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private lazy var adapter: WireGuardAdapter = {
        WireGuardAdapter(with: self) { level, message in
            os_log("%{public}s", log: .default, type: level == .error ? .error : .info, message)
        }
    }()

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let settings = protocolConfiguration as? NETunnelProviderProtocol,
              let text = settings.providerConfiguration?["wgQuickConfig"] as? String
        else {
            completionHandler(TunnelError.noConfiguration)
            return
        }

        let configuration: TunnelConfiguration
        do {
            configuration = try TunnelConfiguration(fromWgQuickConfig: text, called: "QP VPN")
        } catch {
            completionHandler(TunnelError.badConfiguration(String(describing: error)))
            return
        }

        adapter.start(tunnelConfiguration: configuration) { error in
            if let error {
                completionHandler(TunnelError.adapter(String(describing: error)))
                return
            }
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        adapter.stop { _ in
            completionHandler()
        }
    }

    /// Приложение спрашивает счётчики трафика.
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let request = String(data: messageData, encoding: .utf8), request == "traffic" else {
            completionHandler?(nil)
            return
        }

        adapter.getRuntimeConfiguration { runtime in
            var rx: Int64 = 0
            var tx: Int64 = 0

            for line in (runtime ?? "").split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2, let value = Int64(parts[1]) else { continue }
                if parts[0] == "rx_bytes" { rx += value }
                if parts[0] == "tx_bytes" { tx += value }
            }

            let answer = try? JSONSerialization.data(withJSONObject: ["rx": rx, "tx": tx])
            completionHandler?(answer)
        }
    }

    enum TunnelError: LocalizedError {
        case noConfiguration
        case badConfiguration(String)
        case adapter(String)

        var errorDescription: String? {
            switch self {
            case .noConfiguration:
                return "Ключ не найден. Добавьте его в приложении заново."
            case .badConfiguration(let details):
                return "Ключ не подошёл: \(details)"
            case .adapter(let details):
                return "Туннель не поднялся: \(details)"
            }
        }
    }
}
