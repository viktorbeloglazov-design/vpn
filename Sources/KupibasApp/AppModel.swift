import Foundation
import Combine
import ServiceManagement
import KupibasCore

/// Состояние интерфейса. Всё выполняется на главном потоке:
/// таймер обновляет статус, правки конфигурации сохраняются с небольшой задержкой.
final class AppModel: ObservableObject {

    @Published var config: TunnelConfig
    @Published var status: TunnelStatus
    @Published var saveError: String?
    @Published var ipInfo: IPInfo?
    @Published var ipError: String?
    @Published var isCheckingIP = false
    @Published var launchAtLogin: Bool

    private var timer: Timer?
    private var saveWorkItem: DispatchWorkItem?

    init() {
        self.config = ConfigStore.loadConfig()
        self.status = ConfigStore.loadStatus()
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        startTimer()
    }

    // MARK: - Состояние службы

    var isHelperInstalled: Bool { ConfigStore.isInstalled }

    var isDaemonRunning: Bool { status.isDaemonAlive }

    var isOn: Bool { config.enabled }

    /// Короткая строка для шапки окна и меню.
    var stateText: String {
        if !isHelperInstalled { return "Служба не установлена" }
        if !isDaemonRunning { return "Служба не отвечает" }
        if config.enabled && !status.message.isEmpty && status.state != .connected {
            return status.message
        }
        return status.state.title
    }

    // MARK: - Управление

    func toggle() {
        setEnabled(!config.enabled)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, let error = config.server.validationError {
            saveError = "Сначала заполните параметры сервера: \(error)"
            return
        }
        config.enabled = enabled
        saveNow()
        if enabled { ipInfo = nil }
    }

    func setMode(_ mode: TunnelMode) {
        config.mode = mode
        scheduleSave()
    }

    func addRule(kind: RuleKind, value: String, note: String = "") -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        if let error = Validation.ruleError(kind: kind, value: trimmed) { return error }
        if config.rules.contains(where: { $0.kind == kind && $0.value.lowercased() == trimmed }) {
            return "Такое правило уже есть."
        }
        config.rules.append(RoutingRule(kind: kind, value: trimmed, enabled: true, note: note))
        scheduleSave()
        return nil
    }

    func addPreset(_ preset: RulePreset) {
        for rule in preset.rules {
            let exists = config.rules.contains {
                $0.kind == rule.kind && $0.value.lowercased() == rule.value.lowercased()
            }
            if !exists { config.rules.append(rule) }
        }
        scheduleSave()
    }

    func removeRules(ids: Set<String>) {
        config.rules.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    func setRuleEnabled(id: String, enabled: Bool) {
        guard let index = config.rules.firstIndex(where: { $0.id == id }) else { return }
        config.rules[index].enabled = enabled
        scheduleSave()
    }

    func applyServer(_ server: ServerConfig) {
        config.server = server
        saveNow()
    }

    // MARK: - Сохранение

    func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            try ConfigStore.saveConfig(config)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Обновление статуса

    private func startTimer() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refreshStatus() {
        let fresh = ConfigStore.loadStatus()
        if fresh != status { status = fresh }
    }

    // MARK: - Проверка внешнего IP

    func checkIP() {
        guard !isCheckingIP else { return }
        isCheckingIP = true
        ipError = nil
        IPCheck.fetch { [weak self] result in
            guard let self else { return }
            self.isCheckingIP = false
            switch result {
            case .success(let info):
                self.ipInfo = info
                self.ipError = nil
            case .failure(let error):
                self.ipInfo = nil
                self.ipError = error.localizedDescription
            }
        }
    }

    // MARK: - Автозапуск

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            saveError = "Не удалось изменить автозапуск: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Журнал

    func openLog() {
        NSWorkspaceOpener.open(path: Paths.logFile)
    }
}
