import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KupibasCore

/// Вкладка «Сервер»: параметры выходного узла в Казахстане.
struct ServerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showImport = false
    @State private var showPrivateKey = false
    @State private var importNote: String?
    @State private var importFailed = false
    @State private var isDropTarget = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Button("Открыть файл конфига…") { chooseConfigFile() }
                        .keyboardShortcut("o")
                    Button("Вставить текстом…") { showImport = true }
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

                dropZone

                if let importNote {
                    Text(importNote)
                        .font(.caption)
                        .foregroundColor(importFailed ? .red : .green)
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

    /// Файл конфига можно не только выбрать кнопкой, но и бросить сюда мышью.
    private var dropZone: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .foregroundColor(isDropTarget ? .accentColor : .secondary)
            Text(isDropTarget
                 ? "Отпустите — прочитаю конфиг"
                 : "Перетащите сюда файл .conf от вашего сервера или нажмите «Открыть файл конфига…»")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(isDropTarget ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundColor(isDropTarget ? .accentColor : .secondary.opacity(0.4))
        )
        .cornerRadius(8)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { load(from: url) }
            }
            return true
        }
    }

    /// Стандартное окно macOS «Открыть».
    private func chooseConfigFile() {
        let panel = NSOpenPanel()
        panel.title = "Конфигурация WireGuard"
        panel.message = "Выберите файл .conf, который выдал ваш сервер"
        panel.prompt = "Открыть"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        var types: [UTType] = [.plainText, .text, .data]
        if let conf = UTType(filenameExtension: "conf") {
            types.insert(conf, at: 0)
        }
        panel.allowedContentTypes = types

        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(from: url)
    }

    /// Читает файл и подставляет параметры сервера.
    private func load(from url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let text = try readText(at: url)
            let server = try WireGuardConfig.parse(text, name: serverName(for: url))
            model.applyServer(server)
            importNote = "Загружено из «\(url.lastPathComponent)»."
            importFailed = false
        } catch {
            importNote = "«\(url.lastPathComponent)»: \(error.localizedDescription)"
            importFailed = true
        }
    }

    /// Конфиги иногда сохраняют не в UTF-8 — пробуем запасные кодировки.
    private func readText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for encoding in [String.Encoding.utf8, .utf16, .isoLatin1, .windowsCP1251] {
            if let text = String(data: data, encoding: encoding), text.contains("[Interface]") {
                return text
            }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        throw WireGuardConfig.ParseError.invalid("Файл не похож на текстовый конфиг WireGuard.")
    }

    /// Имя сервера: оставляем заданное пользователем, иначе берём имя файла.
    private func serverName(for url: URL) -> String {
        let current = model.config.server.name.trimmingCharacters(in: .whitespaces)
        if !current.isEmpty && current != "KZ" { return current }
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? "KZ" : base
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
