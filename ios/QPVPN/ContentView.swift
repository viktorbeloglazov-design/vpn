import SwiftUI
import UIKit

/// Фирменные цвета: те же, что в версиях для Android, Mac и Windows.
enum Brand {
    static let sky = Color(red: 0.23, green: 0.75, blue: 0.91)
    static let ocean = Color(red: 0.05, green: 0.50, blue: 0.66)
    static let connected = Color(red: 0.18, green: 0.75, blue: 0.53)
    static let waiting = Color(red: 0.89, green: 0.64, blue: 0.24)
    static let danger = Color(red: 0.89, green: 0.41, blue: 0.36)
    static let background = Color(red: 0.04, green: 0.06, blue: 0.08)
    static let surface = Color(red: 0.08, green: 0.11, blue: 0.14)
    static let outline = Color(red: 0.20, green: 0.26, blue: 0.30)
    static let muted = Color(red: 0.62, green: 0.70, blue: 0.75)
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showScanner = false
    @State private var showAdvanced = false
    @State private var showInside = false

    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    header
                    powerCard
                    masterCard
                    workCard
                    keyCard
                    checkCard
                    advancedSection
                    Text("QP VPN 1.0 · AmneziaWG и WireGuard")
                        .font(.caption2)
                        .foregroundColor(Brand.muted)
                        .padding(.top, 6)
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $showScanner) {
            QRScannerView { payload in
                showScanner = false
                Task { await model.importPayload(payload, source: "QR-кода") }
            } onClose: {
                showScanner = false
            }
        }
        .onReceive(ticker) { _ in
            Task { await model.refreshTraffic() }
        }
    }

    // MARK: - Куски экрана

    private var header: some View {
        VStack(spacing: 4) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 40)
            Text("Premium VPN")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Brand.sky)
            Text("Special for Kupibas Group")
                .font(.caption2)
                .foregroundColor(Brand.muted)
        }
        .padding(.bottom, 4)
    }

    private var powerCard: some View {
        Card {
            VStack(spacing: 10) {
                Button {
                    model.tunnel.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(model.tunnel.state == .connected ? Brand.ocean : Brand.surface)
                            .overlay(Circle().strokeBorder(stateColor, lineWidth: 2))
                        VStack(spacing: 4) {
                            Image(systemName: "power")
                                .font(.system(size: 30, weight: .semibold))
                            Text(model.tunnel.state == .connected ? "Выключить" : "Включить")
                                .font(.callout.weight(.semibold))
                        }
                        .foregroundColor(.white)
                    }
                    .frame(width: 148, height: 148)
                }
                .buttonStyle(.plain)
                .disabled(!model.hasProfile || model.busy)
                .opacity(model.hasProfile ? 1 : 0.5)

                Text(model.tunnel.state.title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(stateColor)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Brand.muted)
                    .multilineTextAlignment(.center)

                if model.tunnel.state == .connected {
                    HStack(spacing: 24) {
                        counter(title: "ПРИНЯТО", value: model.rxBytes)
                        counter(title: "ОТПРАВЛЕНО", value: model.txBytes)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var masterCard: some View {
        Card(highlighted: model.config.mainFilter) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $model.config.mainFilter) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Обход блокировок").font(.headline)
                        Text("\(MasterFilter.count) сервисов · нейросети, соцсети, мессенджеры, видео, работа")
                            .font(.caption2)
                            .foregroundColor(Brand.muted)
                    }
                }
                .tint(Brand.ocean)

                Text(model.config.mainFilter
                     ? "Через VPN идут только эти сервисы. Всё остальное — банки, госуслуги, маркетплейсы, любой российский сайт — работает напрямую."
                     : "Выключен: маршруты задаются вручную в расширенных настройках.")
                    .font(.caption)
                    .foregroundColor(Brand.muted)

                Button(showInside ? "Свернуть список" : "Что внутри") {
                    withAnimation { showInside.toggle() }
                }
                .font(.caption)
                .foregroundColor(Brand.sky)

                if showInside {
                    ForEach(MasterFilter.sections, id: \.title) { section in
                        HStack {
                            Text(section.title).font(.caption)
                            Spacer()
                            Text("\(section.domains.count)")
                                .font(.caption.monospaced())
                                .foregroundColor(Brand.muted)
                        }
                    }
                }
            }
        }
    }

    private var workCard: some View {
        Card(highlighted: model.config.workFilter) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $model.config.workFilter) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Рабочие ресурсы").font(.headline)
                        Text("\(WorkFilter.count) адреса · заложены в приложение")
                            .font(.caption2)
                            .foregroundColor(Brand.muted)
                    }
                }
                .tint(Brand.ocean)

                Text(model.config.workFilter
                     ? "Включён: эти ресурсы идут через VPN — даже если всё остальное идёт напрямую."
                     : "Выключен: эти ресурсы идут напрямую, с домашнего адреса.")
                    .font(.caption)
                    .foregroundColor(Brand.muted)

                ForEach(WorkFilter.resources, id: \.url) { resource in
                    HStack {
                        Text(resource.title).font(.caption)
                        Spacer()
                        Text(resource.url)
                            .font(.caption2.monospaced())
                            .foregroundColor(Brand.muted)
                    }
                }
            }
        }
    }

    private var keyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ключ доступа").font(.headline)
                Text(model.hasProfile ? model.profileSummary : "Ключа нет. Отсканируйте QR-код или вставьте ссылку vpn://.")
                    .font(.caption)
                    .foregroundColor(Brand.muted)

                action("Сканировать QR-код", icon: "qrcode.viewfinder") { showScanner = true }
                action("Вставить ключ из буфера", icon: "doc.on.clipboard") {
                    let text = UIPasteboard.general.string ?? ""
                    Task { await model.importPayload(text, source: "буфера обмена") }
                }
                if model.hasProfile {
                    action("Удалить ключ", icon: "trash") {
                        Task { await model.removeProfile() }
                    }
                }

                if !model.note.isEmpty {
                    Text(model.note)
                        .font(.caption)
                        .foregroundColor(model.noteIsError ? Brand.danger : Brand.connected)
                }
            }
        }
    }

    private var checkCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Проверка").font(.headline)
                Text("Посмотрите, из какой страны вас видят сайты.")
                    .font(.caption)
                    .foregroundColor(Brand.muted)
                action(model.checkingIp ? "Проверяю…" : "Проверить мой IP", icon: "globe") {
                    Task { await model.checkIp() }
                }
                if !model.ipText.isEmpty {
                    Text(model.ipText)
                        .font(.caption.monospaced())
                        .foregroundColor(model.ipIsKazakhstan ? Brand.connected : Brand.waiting)
                }
            }
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    if model.config.mainFilter {
                        Text("Главный фильтр включён — он задаёт маршруты сам. Настройки ниже начнут действовать, когда вы его выключите.")
                            .font(.caption2)
                            .foregroundColor(Brand.waiting)
                    }

                    Text("Режим маршрутизации").font(.subheadline.weight(.semibold))
                    Picker("Режим", selection: $model.config.mode) {
                        ForEach(TunnelMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    Toggle("Российская зона мимо VPN", isOn: $model.config.bypassRuZone)
                        .font(.subheadline)
                        .tint(Brand.ocean)
                    Text("Встроенный список: \(RuZone.count()) подсетей России.")
                        .font(.caption2)
                        .foregroundColor(Brand.muted)

                    Toggle("DNS-серверы из профиля", isOn: $model.config.useTunnelDns)
                        .font(.subheadline)
                        .tint(Brand.ocean)

                    if model.tunnel.routeCount > 0 {
                        Text("Сейчас в туннеле маршрутов: \(model.tunnel.routeCount)")
                            .font(.caption2)
                            .foregroundColor(Brand.muted)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Расширенные настройки")
                .font(.subheadline)
                .foregroundColor(Brand.muted)
        }
        .tint(Brand.muted)
    }

    // MARK: - Мелочи

    private var stateColor: Color {
        switch model.tunnel.state {
        case .connected: return Brand.connected
        case .connecting: return Brand.waiting
        case .failed: return Brand.danger
        default: return Brand.outline
        }
    }

    private var subtitle: String {
        switch model.tunnel.state {
        case .failed(let message): return message
        case .connected:
            return "Сервер \(model.tunnel.serverName) · маршрутов: \(model.tunnel.routeCount)"
        case .notReady: return "Добавьте ключ, который вам прислали"
        default: return model.hasProfile ? model.profileSummary : "Ключ не загружен"
        }
    }

    private func counter(title: String, value: Int64) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundColor(Brand.muted)
            Text(Self.bytes(value)).font(.callout.monospaced())
        }
    }

    private func action(_ title: String, icon: String, handler: @escaping () -> Void) -> some View {
        Button(action: handler) {
            HStack {
                Image(systemName: icon)
                Text(title).font(.subheadline)
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Brand.surface)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brand.outline))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
    }

    static func bytes(_ value: Int64) -> String {
        let units = ["Б", "КБ", "МБ", "ГБ", "ТБ"]
        var size = Double(value)
        var unit = 0
        while size >= 1024 && unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        return unit == 0 ? "\(value) Б" : String(format: "%.1f %@", size, units[unit])
    }
}

/// Карточка с рамкой — основа всех разделов.
private struct Card<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Brand.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(highlighted ? Brand.sky : Brand.outline, lineWidth: highlighted ? 1.5 : 1)
            )
            .cornerRadius(16)
            .foregroundColor(.white)
    }
}
