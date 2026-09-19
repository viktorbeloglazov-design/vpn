import SwiftUI
import KupibasCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Form {
                    Section("Поведение туннеля") {
                        Toggle("Использовать DNS-серверы VPN", isOn: $model.config.options.useTunnelDNS)
                            .help("В режиме «только правила» системный DNS не трогается, чтобы не ломать локальную сеть.")
                        Toggle("Отключать IPv6, пока VPN включён", isOn: $model.config.options.disableIPv6)
                            .help("Без этого сайты могут увидеть ваш настоящий IPv6-адрес в обход туннеля.")
                        Toggle("Переподключаться автоматически", isOn: $model.config.options.autoReconnect)
                        Stepper("Пересчитывать IP доменов каждые \(model.config.options.reresolveMinutes) мин",
                                value: $model.config.options.reresolveMinutes,
                                in: 1...60)
                    }

                    Section("Приложение") {
                        Toggle("Запускать при входе в систему", isOn: Binding(
                            get: { model.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        ))
                        .disabled(!model.canManageLaunchAtLogin)
                        if !model.canManageLaunchAtLogin {
                            Text("Доступно после переноса приложения в папку «Программы».")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section("Служба") {
                        LabeledContent("Состояние") {
                            HStack(spacing: 10) {
                                Text(serviceState)
                                    .foregroundColor(model.isDaemonRunning ? .green : .orange)
                                if model.canInstallHelper {
                                    Button(model.isHelperInstalled ? "Переустановить" : "Установить") {
                                        model.installHelper()
                                    }
                                    .disabled(model.isInstallingHelper)
                                    if model.isHelperInstalled {
                                        Button("Удалить") { model.uninstallHelper() }
                                            .disabled(model.isInstallingHelper)
                                    }
                                }
                                if let message = model.installMessage {
                                    Text(message)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        LabeledContent("Интерфейс") {
                            Text(model.status.interfaceName.isEmpty ? "—" : model.status.interfaceName)
                                .font(.body.monospaced())
                        }
                        LabeledContent("Конфигурация") {
                            Text(Paths.configFile).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        LabeledContent("Журнал") {
                            HStack {
                                Text(Paths.logFile).font(.caption.monospaced()).textSelection(.enabled)
                                Button("Открыть") { model.openLog() }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .onAppear { onAppearActions() }

                GroupBox("Команды обслуживания (для сборки из исходников)") {
                    VStack(alignment: .leading, spacing: 8) {
                        commandRow("Установить службу", "sudo ./scripts/install.sh")
                        commandRow("Перезапустить службу",
                                   "sudo launchctl kickstart -k system/\(Paths.daemonLabel)")
                        commandRow("Удалить службу", "sudo ./scripts/uninstall.sh")
                        commandRow("Смотреть журнал", "tail -f \(Paths.logFile)")
                    }
                    .padding(6)
                }
            }
        }
    }

    private func onAppearActions() {
        model.refreshLaunchAtLogin()
    }

    private var serviceState: String {
        if !model.isHelperInstalled { return "не установлена" }
        return model.isDaemonRunning ? "работает" : "не отвечает"
    }

    private func commandRow(_ title: String, _ command: String) -> some View {
        HStack {
            Text(title)
                .frame(width: 180, alignment: .leading)
            Text(command)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer()
            Button("Копировать") {
                NSWorkspaceOpener.copyToPasteboard(command)
            }
            .buttonStyle(.borderless)
        }
    }
}
