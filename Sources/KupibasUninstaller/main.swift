import AppKit
import KupibasCore

/// Мини-программа «Удалить QP VPN».
///
/// Нужна, когда копий программы накопилось несколько и разобраться, какая
/// откуда, уже нельзя. Она показывает всё найденное — с путями и версиями —
/// и убирает выбранное. Терминал для этого не нужен: пароль спрашивает
/// системное окно, как при установке службы.
final class Uninstaller: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private var report = NSTextView()
    private var cleanButton = NSButton()
    private var fullButton = NSButton()
    private var status = NSTextField(labelWithString: "")
    private var items: [Leftovers.Item] = []
    private var runningCopies: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
        scan()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Окно

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Удалить QP VPN"
        window.center()

        let title = NSTextField(labelWithString: "Что нашлось на этом компьютере")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let hint = NSTextField(wrappingLabelWithString:
            "Копии программы могли остаться в разных папках, в Корзине и в памяти. "
            + "Пока старая копия работает, система показывает именно её — "
            + "сколько новых версий ни ставь.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor

        report.isEditable = false
        report.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        report.textContainerInset = NSSize(width: 8, height: 8)

        let scroll = NSScrollView()
        scroll.documentView = report
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        cleanButton = NSButton(title: "Убрать лишние копии", target: self, action: #selector(cleanExtras))
        cleanButton.bezelStyle = .rounded
        cleanButton.toolTip = "Уберёт старые копии и службу. Ключ и настройки останутся."

        fullButton = NSButton(title: "Удалить полностью", target: self, action: #selector(removeEverything))
        fullButton.bezelStyle = .rounded
        fullButton.toolTip = "Уберёт всё, включая ключ и настройки."

        let rescan = NSButton(title: "Поискать заново", target: self, action: #selector(rescan))
        rescan.bezelStyle = .rounded

        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor

        let buttons = NSStackView(views: [cleanButton, fullButton, NSView(), rescan])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [title, hint, scroll, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
            scroll.heightAnchor.constraint(equalToConstant: 320),
        ])
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Поиск

    @objc private func rescan() { scan() }

    private func scan() {
        status.stringValue = "Ищу…"
        cleanButton.isEnabled = false
        fullButton.isEnabled = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = Leftovers.find(currentApp: Bundle.main.bundlePath)
            let running = Leftovers.running()
            DispatchQueue.main.async {
                guard let self else { return }
                self.items = found
                self.runningCopies = running
                self.show()
                self.cleanButton.isEnabled = true
                self.fullButton.isEnabled = true
            }
        }
    }

    private func show() {
        var lines: [String] = []

        let apps = items.filter { $0.kind == .app }
        if apps.isEmpty {
            lines.append("Копий программы не найдено.")
        } else {
            lines.append("КОПИИ ПРОГРАММЫ — \(apps.count)")
            for app in apps {
                let version = app.version.map { "версия \($0)" } ?? "версия неизвестна"
                let working = runningCopies.contains(app.path) ? "  ← сейчас работает" : ""
                lines.append("  \(version), \(megabytes(app.size))\(working)")
                lines.append("    \(app.path)")
            }
        }

        for kind in [Leftovers.Kind.helper, .settings, .log, .leftover] {
            let group = items.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            lines.append("")
            lines.append(kind.rawValue.uppercased())
            for item in group {
                lines.append("  \(item.path)  (\(megabytes(item.size)))")
            }
        }

        if !runningCopies.isEmpty {
            lines.append("")
            lines.append("СЕЙЧАС В ПАМЯТИ — \(runningCopies.count)")
            for path in runningCopies { lines.append("  \(path)") }
            lines.append("  Их нужно завершить, иначе система будет открывать их,")
            lines.append("  а не свежую версию. Кнопки ниже это делают сами.")
        }

        report.string = lines.joined(separator: "\n")
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        status.stringValue = "Всего найдено: \(items.count) — \(megabytes(total))"
    }

    private func megabytes(_ bytes: Int64) -> String {
        bytes <= 0 ? "размер неизвестен"
            : String(format: "%.1f МБ", Double(bytes) / 1_048_576)
    }

    // MARK: - Удаление

    @objc private func cleanExtras() {
        remove(keepSettings: true,
               question: "Убрать старые копии и службу?",
               detail: "Ключ и настройки останутся на месте — программой можно будет "
                     + "пользоваться дальше. Работающие копии будут завершены.")
    }

    @objc private func removeEverything() {
        remove(keepSettings: false,
               question: "Удалить QP VPN полностью?",
               detail: "Будут удалены все копии программы, служба, настройки и ключ. "
                     + "Чтобы пользоваться снова, ключ придётся загрузить заново.")
    }

    private func remove(keepSettings: Bool, question: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = detail
        alert.addButton(withTitle: keepSettings ? "Убрать" : "Удалить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Себя не удаляем: иначе программа исчезнет на середине работы.
        let apps = items
            .filter { $0.kind == .app && !$0.isCurrent }
            .map(\.path)

        status.stringValue = "Удаляю…"
        cleanButton.isEnabled = false
        fullButton.isEnabled = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = Remover.run(apps: apps, keepSettings: keepSettings)
            DispatchQueue.main.async {
                guard let self else { return }
                self.cleanButton.isEnabled = true
                self.fullButton.isEnabled = true
                switch outcome {
                case .done(let log):
                    self.report.string = log
                    self.status.stringValue = "Готово. Нажмите «Поискать заново», чтобы проверить."
                case .cancelled:
                    self.status.stringValue = "Отменено."
                case .failed(let message):
                    self.status.stringValue = message
                }
            }
        }
    }
}

let application = NSApplication.shared
let delegate = Uninstaller()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
