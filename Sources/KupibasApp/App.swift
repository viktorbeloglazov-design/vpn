import SwiftUI
import AppKit
import KupibasCore

@main
struct KupibasVPNApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Kupibas VPN", id: "main") {
            MainView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 560)
        }
        .defaultSize(width: 820, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            Image(systemName: menuBarIcon)
        }
    }

    private var menuBarIcon: String {
        switch model.status.state {
        case .connected: return "shield.lefthalf.filled"
        case .connecting: return "shield.lefthalf.filled.slash"
        case .error: return "exclamationmark.shield"
        case .disconnected: return "shield"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
