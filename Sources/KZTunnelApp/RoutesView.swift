import SwiftUI
import KZTunnelCore

/// Вкладка «Маршруты»: режим сплит-туннеля и список правил.
struct RoutesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newKind: RuleKind = .domain
    @State private var newValue = ""
    @State private var addError: String?
    @State private var selection = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeSection
            Divider()
            addSection
            rulesList
            footer
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Что идёт через VPN", selection: Binding(
                get: { model.config.mode },
                set: { model.setMode($0) }
            )) {
                ForEach(TunnelMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(model.config.mode.subtitle)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("", selection: $newKind) {
                    ForEach(RuleKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                TextField(newKind == .domain ? "kaspi.kz" : "92.46.0.0/16", text: $newValue)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addRule() }

                Button("Добавить") { addRule() }
                    .disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)

                Menu("Готовые наборы") {
                    ForEach(Presets.all) { preset in
                        Button("\(preset.title) — \(preset.mode.title.lowercased())") {
                            model.addPreset(preset)
                        }
                    }
                }
                .frame(width: 170)
            }

            if let addError {
                Text(addError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var rulesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.config.rules.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(model.config.rules) { rule in
                        ruleRow(rule)
                            .tag(rule.id)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 180)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Правил пока нет.")
                .foregroundColor(.secondary)
            Text(model.config.mode == .include
                 ? "В режиме «только правила» без правил через VPN не пойдёт ничего."
                 : "Без правил весь трафик идёт через VPN.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private func ruleRow(_ rule: RoutingRule) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { model.setRuleEnabled(id: rule.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)

            Image(systemName: rule.kind == .domain ? "globe" : "number")
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(rule.value)
                .font(.body.monospaced())
                .foregroundColor(rule.enabled ? .primary : .secondary)

            if !rule.note.isEmpty {
                Text(rule.note)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(destinationLabel)
                .font(.caption)
                .foregroundColor(model.config.mode == .include ? .green : .orange)

            Button(action: { model.removeRules(ids: [rule.id]) }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Удалить правило")
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            Button("Удалить выбранные") {
                model.removeRules(ids: selection)
                selection = []
            }
            .disabled(selection.isEmpty)

            Spacer()

            Text(hint)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var destinationLabel: String {
        switch model.config.mode {
        case .full: return "не используется"
        case .include: return "через VPN"
        case .exclude: return "напрямую"
        }
    }

    private var hint: String {
        switch model.config.mode {
        case .full:
            return "Правила вступят в силу при переключении режима."
        case .include, .exclude:
            return "Домены пересчитываются в IP каждые \(model.config.options.reresolveMinutes) мин."
        }
    }

    private func addRule() {
        let value = newValue
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let error = model.addRule(kind: newKind, value: value) {
            addError = error
        } else {
            addError = nil
            newValue = ""
        }
    }
}
