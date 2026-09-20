import AppKit
import SwiftUI
import Combine
import KupibasCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var model: AppModel?
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Жизненный цикл

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.log("приложение запустилось")

        let model = AppModel()
        self.model = model
        Diagnostics.log("модель создана")

        buildMainMenu()
        Diagnostics.log("главное меню собрано")

        buildStatusItem(model: model)
        Diagnostics.log("значок в строке меню создан")

        showWindow()
        NSApp.activate(ignoringOtherApps: true)
        Diagnostics.log("окно показано — запуск завершён")

        // Приложение обновляют перетаскиванием, а служба остаётся прежней.
        // Догоняем её сами: иначе в приложении новая логика, а работает
        // старая служба — и человек видит ошибку, которой уже нет в коде.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak model] in
            model?.updateHelperIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Приложение живёт в строке меню и после закрытия окна.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: - Окно

    @objc func showWindow() {
        guard let model else { return }

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: MainView().environmentObject(model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QP VPN"
        window.contentView = hosting
        window.minSize = NSSize(width: 720, height: 560)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("QPVPNMainWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
    }

    // MARK: - Главное меню

    /// Без собственного меню в приложении не работают ни ⌘Q, ни вставка в поля,
    /// поэтому собираем минимальный набор руками.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "О программе QP VPN",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Скрыть QP VPN",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Выйти",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Правка")
        editMenu.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Окно")
        windowMenu.addItem(withTitle: "Показать окно QP VPN",
                           action: #selector(showWindow),
                           keyEquivalent: "0")
        windowMenu.addItem(withTitle: "Свернуть", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenuItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Строка меню

    private func buildStatusItem(model: AppModel) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "shield", accessibilityDescription: "QP VPN")
        item.button?.toolTip = "QP VPN"

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        // Значок меняется вслед за состоянием туннеля.
        model.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateStatusIcon(for: status.state, enabled: model.isOn)
            }
            .store(in: &cancellables)
    }

    /// Значок вверху экрана: сразу видно, работает VPN или нет.
    ///
    /// Подключённый туннель — сплошной щит, всё остальное — контур, поэтому
    /// состояние читается боковым зрением, не наводя курсор.
    private func updateStatusIcon(for state: TunnelState, enabled: Bool) {
        let symbol: String
        let tooltip: String
        switch state {
        case .connected:
            symbol = "shield.fill"
            tooltip = "QP VPN подключён"
        case .connecting:
            symbol = "shield.lefthalf.filled"
            tooltip = "QP VPN подключается"
        case .error:
            symbol = "exclamationmark.shield"
            tooltip = "QP VPN: ошибка"
        case .disconnected:
            symbol = enabled ? "shield.lefthalf.filled" : "shield"
            tooltip = enabled ? "QP VPN подключается" : "QP VPN выключен"
        }
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "QP VPN")
            ?? NSImage(systemSymbolName: "shield", accessibilityDescription: "QP VPN")
        button.toolTip = tooltip
    }

    @objc private func toggleTunnel() {
        model?.toggle()
    }

    @objc private func toggleWorkFilter() {
        guard let model else { return }
        model.setWorkFilter(!model.config.workFilter)
    }
}

// MARK: - Содержимое меню в строке состояния

extension AppDelegate: NSMenuDelegate {

    /// Меню собирается заново в момент открытия — так в нём всегда свежие цифры.
    func menuWillOpen(_ menu: NSMenu) {
        guard let model else { return }
        menu.removeAllItems()

        let header = NSMenuItem(title: "QP VPN — \(model.stateText)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let toggle = NSMenuItem(
            title: model.isOn ? "Выключить VPN" : "Включить VPN",
            action: #selector(toggleTunnel),
            keyEquivalent: "t"
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(NSMenuItem.separator())

        // Маршрутизация зашита — выбирать нечего, показываем как есть.
        let routing = NSMenuItem(title: "Обход блокировок · российские сайты напрямую",
                                 action: nil,
                                 keyEquivalent: "")
        routing.isEnabled = false
        menu.addItem(routing)

        // Единственный переключатель программы.
        let work = NSMenuItem(title: "Рабочие ресурсы через VPN",
                              action: #selector(toggleWorkFilter),
                              keyEquivalent: "")
        work.target = self
        work.state = model.config.workFilter ? .on : .off
        menu.addItem(work)

        if model.status.state == .connected {
            menu.addItem(NSMenuItem.separator())
            let traffic = NSMenuItem(
                title: "Трафик: ↓ \(Formatting.bytes(model.status.rxBytes))  ↑ \(Formatting.bytes(model.status.txBytes))",
                action: nil,
                keyEquivalent: ""
            )
            traffic.isEnabled = false
            menu.addItem(traffic)
        }

        menu.addItem(NSMenuItem.separator())

        let open = NSMenuItem(title: "Открыть окно…", action: #selector(showWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let quit = NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }
}
