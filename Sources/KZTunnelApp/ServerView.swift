import SwiftUI
import KZTunnelCore

/// Вкладка «Сервер»: параметры выходного узла в Казахстане.
struct ServerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showImport = false
    @State private var showPrivateKey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("Вставить конфиг WireGuard…") { showImport = true }
                    Spacer()
                    if let error = model.config.server.validationError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Label("Конфигурация заполнена", systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                Form {
                    TextField("Название", text: $model.config.server.name)
                    TextField("Endpoint (host:port)", text: $model.config.server.endpoint)
                        .font(.body.monospaced())
                    TextField("Публичный ключ сервера", text: $model.config.server.publicKey)
                        .font(.body.monospaced())
                    TextField("Preshared-ключ (необязательно)", text: $model.config.server.presharedKey)
                        .font(.body.monospaced())

                    HStack {
                        if showPrivateKey {
                            TextField("Приватный ключ клиента", text: $model.config.server.privateKey)
                                .font(.body.monospaced())
                        } else {
                            SecureField("Приватный ключ клиента", text: $model.config.server.privateKey)
                        }
                        Button(showPrivateKey ? "Скрыть" : "Показать") {
                            showPrivateKey.toggle()
                        }
                    }

                    TextField("Адрес в туннеле (Address)", text: listBinding(\.addresses))
                        .font(.body.monospaced())
                    TextField("DNS-серверы", text: listBinding(\.dns))
                        .font(.body.monospaced())

                    HStack(spacing: 16) {
                        TextField("MTU", value: $model.config.server.mtu, format: .number)
                            .frame(width: 90)
                        TextField("Keepalive, с", value: $model.config.server.persistentKeepalive, format: .number)
                            .frame(width: 90)
                        Spacer()
                    }
                }
                .formStyle(.grouped)

                Text("""
                Эти данные выдаёт ваш сервер WireGuard в Казахстане. \
                Если сервера ещё нет — разверните его скриптом server/install-wg-kz.sh на VPS \
                у казахстанского хостера и вставьте сюда получившийся клиентский конфиг.
                """)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showImport) {
            ImportConfigSheet { server in
                model.applyServer(server)
                showImport = false
            } onCancel: {
                showImport = false
            }
        }
    }

    /// Списочные поля (Address, DNS) редактируются как строка через запятую.
    private func listBinding(_ keyPath: WritableKeyPath<ServerConfig, [String]>) -> Binding<String> {
        Binding(
            get: { model.config.server[keyPath: keyPath].joined(separator: ", ") },
            set: { model.config.server[keyPath: keyPath] = WireGuardConfig.splitList($0) }
        )
    }
}

/// Импорт стандартного .conf одной вставкой из буфера обмена.
struct ImportConfigSheet: View {
    var onImport: (ServerConfig) -> Void
    var onCancel: () -> Void

    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Вставьте конфиг WireGuard")
                .font(.headline)
            Text("Подойдёт файл .conf от вашего сервера или VPN-провайдера с казахстанским выходом.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minWidth: 520, minHeight: 280)
                .border(Color.secondary.opacity(0.3))

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Button("Вставить из буфера") {
                    if let clipboard = NSPasteboard.general.string(forType: .string) {
                        text = clipboard
                    }
                }
                Spacer()
                Button("Отмена", role: .cancel) { onCancel() }
                Button("Импортировать") { importConfig() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
    }

    private func importConfig() {
        do {
            let server = try WireGuardConfig.parse(text)
            error = nil
            onImport(server)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
