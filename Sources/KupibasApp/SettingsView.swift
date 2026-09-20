import SwiftUI
import KupibasCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Form {
                    Section("Размер пакета (MTU)") {
                        Picker("", selection: Binding(
                            get: { model.config.options.mtu },
                            set: { model.setMTU($0) }
                        )) {
                            Text("1420").tag(1420)
                            Text("Из ключа").tag(0)
                            Text("1380").tag(1380)
                            Text("1280").tag(1280)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text("От него зависит скорость. Чем больше — тем быстрее, но если сеть "
                             + "не пропускает такие пакеты, страницы наоборот встают. Порядок "
                             + "подбора: 1420 → из ключа → 1380 → 1280. "
                             + "Сейчас в ключе: \(model.config.server.mtu).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("При смене туннель переподнимется сам — связь пропадёт на секунду.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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

                    Section("Диагностика") {
                        Text(model.diagnosticsReport())
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Скопировать отчёт") { model.copyDiagnostics() }
                        Text("Отчёт можно переслать тому, кто выдал ключ: в нём нет самих ключей, только состояние.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
