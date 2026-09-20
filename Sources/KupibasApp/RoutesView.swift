import SwiftUI
import KupibasCore

/// Вкладка «Главная»: как идёт трафик и единственный переключатель.
///
/// Настраивать маршрутизацию негде и не нужно — она зашита: заблокированные
/// сервисы идут через VPN, российские адреса напрямую. Так же, как в версии
/// для телефона.
struct RoutesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                trafficSection
                Divider()
                workFilterSection
            }
            .padding(.trailing, 4)
        }
    }

    // MARK: - Как идёт трафик

    private var trafficSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Как идёт трафик").font(.headline)
                Text("настраивать ничего не нужно")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            row(icon: "shield.lefthalf.filled",
                color: .accentColor,
                title: "Заблокированные сервисы",
                detail: "Идут через VPN, казахстанский адрес")

            row(icon: "house",
                color: .green,
                title: "Российские сайты",
                detail: russianDetail)

            if model.status.routeCount > 0 {
                HStack {
                    Text("Маршрутов мимо туннеля").foregroundColor(.secondary)
                    Spacer()
                    Text("\(model.status.routeCount)").font(.body.monospacedDigit())
                }
                .font(.callout)
            }
        }
    }

    private var russianDetail: String {
        let count = model.ruZoneCount
        return count > 0
            ? "МАХ, госуслуги, банки, маркетплейсы — напрямую (\(count) подсетей России)"
            : "МАХ, госуслуги, банки, маркетплейсы — напрямую"
    }

    private func row(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: - Единственный переключатель

    private var workFilterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { model.config.workFilter },
                set: { model.setWorkFilter($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Рабочие ресурсы").font(.headline)
                    Text("\(WorkFilter.count) адреса · заложены в приложение")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)

            Text(model.config.workFilter
                 ? "Включён: эти ресурсы идут через VPN — даже если всё остальное идёт напрямую."
                 : "Выключен: эти ресурсы идут напрямую, с домашнего адреса.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(WorkFilter.resources, id: \.url) { resource in
                HStack(spacing: 10) {
                    Text(resource.title)
                        .frame(width: 70, alignment: .leading)
                    Text(resource.url)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                }
            }
        }
    }
}
