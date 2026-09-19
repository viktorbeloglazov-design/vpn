import SwiftUI
import AppKit
import KupibasCore

struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Kupibas VPN — \(model.stateText)")

        Button(model.isOn ? "Выключить VPN" : "Включить VPN") {
            model.toggle()
        }
        .keyboardShortcut("t")

        Divider()

        ForEach(TunnelMode.allCases, id: \.self) { mode in
            Button(menuTitle(for: mode)) {
                model.setMode(mode)
            }
        }

        Divider()

        if model.status.state == .connected {
            Text("Трафик: ↓ \(Formatting.bytes(model.status.rxBytes))  ↑ \(Formatting.bytes(model.status.txBytes))")
        }

        Button("Открыть окно…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Button("Выйти") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func menuTitle(for mode: TunnelMode) -> String {
        (model.config.mode == mode ? "✓ " : "   ") + mode.title
    }
}
