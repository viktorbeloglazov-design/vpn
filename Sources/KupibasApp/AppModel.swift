import Foundation
import AppKit
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
    @Published var isInstallingHelper = false
    @Published var installMessage: String?

    /// Служба осталась от прошлой версии приложения.
    @Published var helperNeedsUpdate = false

    /// Свежая версия, если она вышла; пусто — обновлять нечего.
    @Published var updateVersion = ""
    @Published var updateBusy = false
    @Published var updateNote = ""

    private var helperUpdateAttempted = false

    private var ruZoneCountCache: Int?

    private var timer: Timer?
    private var saveWorkItem: DispatchWorkItem?

    init() {
        Diagnostics.log("модель: читаю настройки")
        self.config = ConfigStore.loadConfig()
        self.status = ConfigStore.loadStatus()
        // Про автозапуск спрашиваем систему не здесь: обращение к SMAppService
        // на самом старте способно уронить приложение, подписанное своим
        // сертификатом. Состояние подтянется, когда откроют «Настройки».
        self.launchAtLogin = false
        startTimer()
        Diagnostics.log("модель: готова")
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

    /// Единственная настройка маршрутизации, которая осталась у человека.
    ///
    /// Всё остальное зашито: заблокированные сервисы идут через VPN,
    /// российские адреса — напрямую, менять это негде и не нужно.
    func setWorkFilter(_ enabled: Bool) {
        config.workFilter = enabled
        scheduleSave()
    }

    /// Размер пакета: 0 — подобрать самому.
    func setMTU(_ value: Int) {
        config.options.mtu = value
        saveNow()
    }

    /// Запасной вход: узел, который пересылает пакеты на сервер.
    func setBackupEndpoint(_ value: String) {
        config.backupEndpoint = value.trimmingCharacters(in: .whitespaces)
        scheduleSave()
    }

    /// Сколько подсетей России знает программа — показываем в подписи.
    var ruZoneCount: Int {
        if let cached = ruZoneCountCache { return cached }

        var paths = [RuZone.installedPath]
        if let bundled = Bundle.main.path(forResource: "ru_ipv4", ofType: "txt") {
            paths.append(bundled)
        }
        let count = RuZone.networks(extraPaths: paths).count
        ruZoneCountCache = count
        return count
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

    /// Автозапуском управляет система, и она требует, чтобы приложение лежало
    /// в «Программах». Из папки загрузок или с образа это не работает.
    var canManageLaunchAtLogin: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications")
    }

    /// Спрашивает систему о текущем состоянии автозапуска.
    func refreshLaunchAtLogin() {
        guard canManageLaunchAtLogin else {
            launchAtLogin = false
            return
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard canManageLaunchAtLogin else {
            saveError = "Автозапуск работает, только когда приложение лежит в папке «Программы»."
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            saveError = "Не удалось изменить автозапуск: \(error.localizedDescription)"
            refreshLaunchAtLogin()
        }
    }

    // MARK: - Служба

    /// Можно ли поставить службу кнопкой (приложение запущено из собранного бандла).
    var canInstallHelper: Bool { HelperInstaller.isBundled }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Из какой версии приложения поставлена служба. nil — отметки нет.
    var installedHelperVersion: String? {
        guard let text = try? String(contentsOfFile: Paths.helperVersionFile, encoding: .utf8) else {
            return nil
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func refreshHelperVersion() {
        guard isHelperInstalled, !appVersion.isEmpty else {
            helperNeedsUpdate = false
            return
        }
        helperNeedsUpdate = installedHelperVersion != appVersion
    }

    /// Обновляет службу сама, если приложение обновили, а её — нет.
    ///
    /// Иначе получается худшее из возможного: в приложении новая логика, а
    /// работает старая служба — и человек видит ошибку, которой в новом коде
    /// уже нет. Спрашиваем пароль один раз за обновление.
    func updateHelperIfNeeded() {
        guard !helperUpdateAttempted, canInstallHelper else { return }
        refreshHelperVersion()
        guard helperNeedsUpdate else { return }

        helperUpdateAttempted = true
        installMessage = "Обновляю службу до версии \(appVersion)…"
        installHelper()
        refreshHelperVersion()
        if !helperNeedsUpdate {
            installMessage = "Служба обновлена до версии \(appVersion)."
            status = ConfigStore.loadStatus()
        }
    }

    func installHelper() {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true
        installMessage = nil
        let error = HelperInstaller.run(.install)
        isInstallingHelper = false
        if let error {
            saveError = error
        } else {
            config = ConfigStore.loadConfig()
            installMessage = "Служба установлена."
        }
        refreshHelperVersion()
    }

    func uninstallHelper() {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true
        installMessage = nil
        let error = HelperInstaller.run(.uninstall)
        isInstallingHelper = false
        if let error {
            saveError = error
        } else {
            installMessage = "Служба удалена."
        }
    }

    // MARK: - Куда на самом деле идёт трафик

    @Published var routeCheck: [RouteProbe.Result] = []
    @Published var routeCheckNote: String = ""

    /// Спрашивает систему, идут ли российские сервисы мимо туннеля.
    ///
    /// Это единственный способ ответить на «МАХ не грузит файлы» точно,
    /// а не догадками: система знает, через какой интерфейс уйдёт пакет.
    func checkRouting() {
        routeCheckNote = "Проверяю…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = RouteProbe.check()
            let note = RouteProbe.summary(results)
            DispatchQueue.main.async {
                self?.routeCheck = results
                self?.routeCheckNote = note
            }
        }
    }

    // MARK: - Лишние копии программы

    /// Сколько копий программы нашлось, кроме этой.
    @Published var otherCopies: Int = 0
    @Published var cleanupNote: String = ""
    @Published var cleanupBusy: Bool = false

    /// Ищет другие копии программы на компьютере.
    ///
    /// Программа ставится перетаскиванием, поэтому копий легко набирается
    /// несколько. Работает при этом та, что уже в памяти, — и человек,
    /// поставив новую версию, продолжает видеть старую.
    func scanCopies() {
        cleanupNote = "Ищу…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let mine = Bundle.main.bundlePath
            let others = Leftovers.applications().filter { $0 != mine }
            let running = Leftovers.running().filter { $0 != mine }
            DispatchQueue.main.async {
                guard let self else { return }
                self.otherCopies = others.count
                if others.isEmpty {
                    self.cleanupNote = "Других копий не найдено — эта единственная."
                    return
                }
                var lines = others.map { path -> String in
                    let version = Leftovers.version(of: path) ?? "версия неизвестна"
                    let mark = running.contains(path) ? " — сейчас работает" : ""
                    return "\(version): \(path)\(mark)"
                }
                if !running.isEmpty {
                    lines.append("Работающие копии будут завершены при уборке.")
                }
                self.cleanupNote = lines.joined(separator: "\n")
            }
        }
    }

    /// Убирает все копии, кроме этой. Ключ и настройки остаются.
    func removeOtherCopies() {
        guard !cleanupBusy else { return }
        let mine = Bundle.main.bundlePath
        let others = Leftovers.applications().filter { $0 != mine }
        guard !others.isEmpty else {
            cleanupNote = "Убирать нечего."
            return
        }

        cleanupBusy = true
        cleanupNote = "Убираю…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let error = HelperInstaller.run(.removeCopies(others))
            DispatchQueue.main.async {
                guard let self else { return }
                self.cleanupBusy = false
                if let error {
                    self.cleanupNote = error
                } else {
                    self.cleanupNote = "Убрано копий: \(others.count). Ключ и настройки на месте."
                    self.scanCopies()
                }
            }
        }
    }

    // MARK: - Обновление приложения

    /// Смотрит, не вышла ли новая версия. Раз в сутки, если не просили иначе.
    func checkForUpdate(force: Bool) {
        let now = Date().timeIntervalSince1970
        if !force, now - config.lastUpdateCheck < UpdateCheck.checkInterval { return }

        if force { updateNote = "Проверяю…" }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let latest = UpdateCheck.latestVersion()
            DispatchQueue.main.async {
                guard let self else { return }
                self.config.lastUpdateCheck = now
                self.saveNow()

                guard let latest else {
                    self.updateNote = force ? "Не удалось проверить — нет связи с хранилищем." : ""
                    return
                }
                if UpdateCheck.isNewer(latest, than: self.appVersion) {
                    self.updateVersion = latest
                    self.updateNote = ""
                    // Дальше — само. Человек за компьютером не должен
                    // следить за версиями: пока он не нажмёт кнопку, он
                    // сидит на старой, а мы об этом не узнаем.
                    self.installUpdate()
                } else {
                    self.updateVersion = ""
                    self.updateNote = force ? "Установлена свежая версия \(self.appVersion)." : ""
                }
            }
        }
    }

    /// Скачивает новую версию, ставит её вместо текущей и перезапускается.
    ///
    /// Запускается само, как только нашлась новая версия: старая программа
    /// закрывается, новая открывается уже обновлённой. Ни нажимать кнопку,
    /// ни перетаскивать что-то в «Программы» человек не должен. Кнопка
    /// остаётся на случай, когда само не вышло.
    func installUpdate() {
        guard !updateBusy else { return }
        updateBusy = true
        updateNote = "Скачиваю…"

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = UpdateCheck.download()
            guard let image else {
                DispatchQueue.main.async {
                    self?.updateBusy = false
                    self?.updateNote = "Скачать не удалось — попробую позже. Можно и нажать «Обновить»."
                }
                return
            }

            DispatchQueue.main.async { self?.updateNote = "Устанавливаю…" }
            let outcome = UpdateCheck.install(image)

            DispatchQueue.main.async {
                guard let self else { return }
                self.updateBusy = false
                switch outcome {
                case .replaced:
                    // Туннель поднимает служба, и она продолжит работать
                    // сама по себе — связь на время перезапуска не рвётся.
                    self.updateNote = "Обновлено. Перезапускаюсь…"
                    UpdateCheck.relaunchAfterQuit()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        NSApp.terminate(nil)
                    }
                case .openedInFinder(let reason):
                    self.updateNote = reason
                }
            }
        }
    }

    // MARK: - Ежедневный отчёт

    /// Складывает отчёт за сегодня в «Документы/QP VPN/отчёты».
    ///
    /// Тот же текст, что и в «Скопировать отчёт», только сам и каждый день:
    /// когда человек говорит «вчера отвалилось», есть на что посмотреть.
    func saveDailyReport() {
        let text = DailyReport.header(version: appVersion) + diagnosticsReport()
        DailyReport.save(text)
    }

    // MARK: - Диагностика

    /// Короткий отчёт о состоянии — его можно переслать тому, кто выдал ключ.
    ///
    /// Ключей внутри нет: только адрес сервера, режим, счётчики и время
    /// последнего ответа сервера. Этого хватает, чтобы понять, где встало.
    func diagnosticsReport() -> String {
        let server = config.server
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let mtu: String
        if config.options.mtu > 0 {
            mtu = "\(config.options.mtu) (задан вручную)"
        } else if status.activeMtu > 0 {
            mtu = "\(status.activeMtu) (подобран автоматически, в ключе \(server.mtu))"
        } else {
            mtu = "\(server.mtu) (из ключа)"
        }

        var lines: [String] = []
        lines.append("QP VPN \(version) для Mac, macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Состояние: \(stateText)")
        lines.append("Служба: \(isHelperInstalled ? (isDaemonRunning ? "работает" : "не отвечает") : "не установлена")")
        lines.append("Режим: обход блокировок (всё, кроме \(ruZoneCount) подсетей РФ)")
        lines.append("Рабочие ресурсы: \(config.workFilter ? "через VPN" : "напрямую")")
        if server.endpoint.isEmpty {
            lines.append("Ключ: не загружен")
        } else {
            lines.append("Сервер: \(server.endpoint)")
            lines.append("Протокол: \(server.protocolName), параметров маскировки: \(server.amneziaParams.count)")
            lines.append("DNS из ключа: \(server.dns.isEmpty ? "нет" : server.dns.joined(separator: ", "))")
            lines.append("MTU: \(mtu)")
        }
        lines.append("Вход: \(status.viaBackupEntry ? "запасной узел" : "сервер напрямую")")
        if !config.backupEndpoint.isEmpty {
            lines.append("Запасной вход: \(config.backupEndpoint)")
        }
        lines.append("Интерфейс: \(status.interfaceName.isEmpty ? "—" : status.interfaceName)")
        lines.append("Маршрутов мимо туннеля: \(status.routeCount)")

        // Куда на самом деле уходят пакеты: по этому видно, работает ли
        // обход, — без него разговор упирается в догадки.
        for result in RouteProbe.check() {
            let path = result.interface.isEmpty
                ? "маршрут не найден"
                : (result.bypassesTunnel ? "напрямую (\(result.interface))"
                                         : "через VPN (\(result.interface))")
            lines.append("  \(result.name): \(path)")
        }
        lines.append("Handshake: \(Formatting.relative(status.lastHandshake))")
        lines.append("Принято/отправлено: \(Formatting.bytes(status.rxBytes)) / \(Formatting.bytes(status.txBytes))")
        return lines.joined(separator: "\n")
    }

    func copyDiagnostics() {
        NSWorkspaceOpener.copyToPasteboard(diagnosticsReport())
        installMessage = "Отчёт скопирован."
    }

    // MARK: - Журнал

    func openLog() {
        NSWorkspaceOpener.open(path: Paths.logFile)
    }
}
