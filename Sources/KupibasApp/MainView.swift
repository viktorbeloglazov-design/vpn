import SwiftUI
import KupibasCore

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            if !model.isHelperInstalled {
                InstallBanner(text: "Служба kupibasvpnd не установлена. Без неё переключатель не сработает.")
            } else if !model.isDaemonRunning {
                InstallBanner(text: "Служба kupibasvpnd не отвечает. Проверьте: sudo launchctl print system/\(Paths.daemonLabel)")
            }

            PowerHeader()
                .padding(18)

            Divider()

            TabView(selection: $selectedTab) {
                RoutesView()
                    .tabItem { Label("Маршруты", systemImage: "arrow.triangle.branch") }
                    .tag(0)
                ServerView()
                    .tabItem { Label("Сервер", systemImage: "server.rack") }
                    .tag(1)
                SettingsView()
                    .tabItem { Label("Настройки", systemImage: "gearshape") }
                    .tag(2)
            }
            .padding(12)
        }
        .onChange(of: model.config) { _ in
            model.scheduleSave()
        }
        .alert("Не удалось сохранить настройки",
               isPresented: Binding(get: { model.saveError != nil },
                                    set: { if !$0 { model.saveError = nil } })) {
            Button("Понятно", role: .cancel) { model.saveError = nil }
        } message: {
            Text(model.saveError ?? "")
        }
    }
}

/// Верхняя панель: кнопка включения, состояние, внешний IP.
struct PowerHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Button(action: { model.toggle() }) {
                ZStack {
                    Circle()
                        .fill(buttonColor.opacity(0.16))
                    Circle()
                        .strokeBorder(buttonColor, lineWidth: 2)
                    Image(systemName: "power")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(buttonColor)
                }
                .frame(width: 74, height: 74)
            }
            .buttonStyle(.plain)
            .help(model.isOn ? "Выключить VPN" : "Включить VPN")

            VStack(alignment: .leading, spacing: 6) {
                Text(model.stateText)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Text(model.config.mode.title)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(6)
                    if model.config.mode != .full {
                        Text("правил активно: \(model.config.activeRules.count) · маршрутов: \(model.status.routeCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                ipRow
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                statLine("Время сессии", model.status.state == .connected
                         ? Formatting.duration(since: model.status.connectedSince) : "—")
                statLine("Handshake", Formatting.relative(model.status.lastHandshake))
                statLine("Принято", Formatting.bytes(model.status.rxBytes))
                statLine("Отправлено", Formatting.bytes(model.status.txBytes))
            }
        }
    }

    private var ipRow: some View {
        HStack(spacing: 8) {
            Button(action: { model.checkIP() }) {
                Label(model.isCheckingIP ? "Проверяю…" : "Проверить мой IP",
                      systemImage: "globe")
            }
            .disabled(model.isCheckingIP)

            if let info = model.ipInfo {
                Text(info.summary)
                    .font(.callout)
                    .foregroundColor(info.isKazakhstan ? .green : .primary)
                    .textSelection(.enabled)
            } else if let error = model.ipError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.top, 2)
    }

    private func statLine(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private var subtitle: String {
        let server = model.config.server
        if server.endpoint.isEmpty { return "Сервер не настроен — откройте вкладку «Сервер»." }
        return "\(server.name) · \(server.endpoint)"
    }

    private var buttonColor: Color {
        switch model.status.state {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .secondary
        }
    }
}

struct InstallBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(text)
                .font(.callout)
            Spacer()
            Button("Скопировать команду установки") {
                NSWorkspaceOpener.copyToPasteboard("sudo ./scripts/install.sh")
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }
}
