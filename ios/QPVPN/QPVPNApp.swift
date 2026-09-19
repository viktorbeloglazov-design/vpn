import SwiftUI

@main
struct QPVPNApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // Ссылку vpn:// можно просто нажать в переписке.
                    Task { await model.importPayload(url.absoluteString, source: "ссылки") }
                }
        }
    }
}
