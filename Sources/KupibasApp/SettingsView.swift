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
                             + "не пропускает такие пакеты, видео и потоковые ответы встают. "
                             + "На «Авто» служба подбирает размер сама при подключении. "
                             + "Сейчас в ключе: \(model.config.server.mtu).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("При смене туннель переподнимется сам — связь пропадёт на секунду.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Section("Эта копия программы") {
                        // Когда копий несколько, первый вопрос — какая из них
                        // сейчас работает. Путь отвечает на него сразу.
                        LabeledContent("Версия") {
                            Text(model.appVersion).foregroundColor(.secondary)
                        }
                        LabeledContent("Откуда запущена") {
                            Text(Bundle.main.bundlePath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        if model.otherCopies > 0 {
                            Text("На компьютере есть ещё копии программы: \(model.otherCopies). "
                                 + "Пока они лежат рядом, система может открывать не ту.")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 10) {
                            Button("Найти все копии") { model.scanCopies() }
                            if model.otherCopies > 0 {
                                Button(model.cleanupBusy ? "Убираю…" : "Убрать лишние копии") {
                                    model.removeOtherCopies()
                                }
                                .disabled(model.cleanupBusy)
                            }
                        }
                        if !model.cleanupNote.isEmpty {
                            Text(model.cleanupNote)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Section("Обновление") {
                        LabeledContent("Версия") {
                            HStack(spacing: 10) {
                                Text(model.updateVersion.isEmpty
                                     ? "установлена \(model.appVersion), проверяется раз в сутки"
                                     : "вышла \(model.updateVersion), установлена \(model.appVersion)")
                                    .foregroundColor(model.updateVersion.isEmpty ? .secondary : .green)
                                Button("Проверить") { model.checkForUpdate(force: true) }
                                if !model.updateVersion.isEmpty {
                                    Button(model.updateBusy ? "Скачиваю…" : "Обновить") {
                                        model.installUpdate()
                                    }
                                    .disabled(model.updateBusy)
                                }
                            }
                        }
                        if !model.updateNote.isEmpty {
                            Text(model.updateNote)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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

                    Section("Запасной вход") {
                        TextField("95.213.0.1:31984", text: Binding(
                            get: { model.config.backupEndpoint },
                            set: { model.setBackupEndpoint($0) }
                        ))
                        Text("Необязательно. Адрес узла-пересыльщика в виде адрес:порт. Служба "
                             + "пробует сервер напрямую, а если он не ответит — этот узел. "
                             + "Ключ менять не нужно.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
                        LabeledContent("Версия") {
                            Text(model.installedHelperVersion.map { "служба \($0) · приложение \(model.appVersion)" }
                                 ?? "служба от старой версии · приложение \(model.appVersion)")
                                .foregroundColor(model.helperNeedsUpdate ? .orange : .secondary)
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
        model.refreshHelperVersion()
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
