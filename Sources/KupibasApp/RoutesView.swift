import SwiftUI
import KupibasCore

/// Вкладка «Главная»: что идёт через VPN и что добавить своего.
///
/// Через VPN идёт только список сервисов — мессенджеры, видео и ИИ.
/// Всё остальное идёт напрямую: российские сайты, банки, маркетплейсы,
/// госуслуги, рабочая почта. Так же, как в версии для телефона.
struct RoutesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                servicesSection
                Divider()
                ownRulesSection
                Divider()
                workFilterSection
            }
            .padding(.trailing, 4)
        }
    }

    // MARK: - Что идёт через VPN

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Через VPN").font(.headline)
                Text("настраивать ничего не нужно")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            row(icon: "message",
                color: .accentColor,
                title: "Мессенджеры",
                detail: "WhatsApp, Instagram, Telegram — вместе с фото и видео")

            row(icon: "play.rectangle",
                color: .accentColor,
                title: "Видео",
                detail: "YouTube")

            row(icon: "sparkles",
                color: .accentColor,
                title: "Искусственный интеллект",
                detail: аиСервисы)

            row(icon: "house",
                color: .green,
                title: "Всё остальное — напрямую",
                detail: "Российские сайты, банки, маркетплейсы, МАХ, госуслуги, "
                    + "почта. Через VPN они не идут, поэтому работают как обычно")

            if model.status.routeCount > 0 {
                HStack {
                    Text("Адресов в туннеле").foregroundColor(.secondary)
                    Spacer()
                    Text("\(model.status.routeCount)").font(.body.monospacedDigit())
                }
                .font(.callout)
            }
        }
    }

    /// Названия ИИ-сервисов из зашитого списка — чтобы не расходились.
    private var аиСервисы: String {
        let мессенджерыИВидео = ["WhatsApp", "Instagram", "Telegram", "YouTube"]
        return VpnServices.titles
            .filter { !мессенджерыИВидео.contains($0) }
            .joined(separator: ", ")
    }

    // MARK: - Свои адреса

    private var ownRulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Свои сайты через VPN").font(.headline)
            Text("Если нужного сервиса нет в списке выше — впишите его здесь, "
                 + "по одному в строке. Можно имя сайта или адрес сети.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: Binding(
                get: { model.ownRulesText },
                set: { model.setOwnRulesText($0) }
            ))
            .font(.body.monospaced())
            .frame(minHeight: 80)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            if let error = model.ownRulesError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Например: example.com или 203.0.113.0/24")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
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

    // MARK: - Рабочие ресурсы

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
                 ? "Включён: эти ресурсы идут через VPN."
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
