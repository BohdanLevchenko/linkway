import LinkwayCore
import SwiftUI

struct RulesPreferencesView: View {
    @ObservedObject var model: PreferencesModel
    @State private var selection: UUID?
    @State private var editor: RuleDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rules run from top to bottom. The first enabled match wins.")
                .font(.caption).foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(model.configuration.rules) { rule in
                    HStack {
                        Toggle("Enable \(rule.name)", isOn: Binding(get: { rule.isEnabled }, set: { enabled in
                            model.update { config in
                                if let index = config.rules.firstIndex(where: { $0.id == rule.id }) {
                                    config.rules[index].isEnabled = enabled
                                }
                            }
                        }))
                        .labelsHidden().toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.name).fontWeight(.medium)
                            Text(summary(rule)).foregroundStyle(.secondary)
                            HStack {
                                if case .open(_, true) = rule.action { badge("Private") }
                                if rule.origin == .remembered { badge("Remembered") }
                            }
                            if case .open(let id, _) = rule.action, !model.availableIDs.contains(id) {
                                Label("Unavailable: \(id.rawValue)", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editor = RuleDraft(rule: rule) }
                        Button { model.deleteRules([rule.id]) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(rule.name)")
                    }
                    .padding(.vertical, 4)
                    .tag(rule.id)
                }
                .onMove { offsets, index in
                    model.update { $0.rules.move(fromOffsets: offsets, toOffset: index) }
                }
                .onDelete { offsets in
                    let ids = Set(offsets.map { model.configuration.rules[$0].id })
                    model.deleteRules(ids)
                }
            }
            .onDeleteCommand {
                if let selection { model.deleteRules([selection]); self.selection = nil }
            }
            .overlay {
                if model.configuration.rules.isEmpty { Text("No rules yet. Add one with +.").foregroundStyle(.secondary) }
            }
            HStack {
                Button { editor = RuleDraft() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add rule")
                Button("Edit…") {
                    if let rule = model.configuration.rules.first(where: { $0.id == selection }) {
                        editor = RuleDraft(rule: rule)
                    }
                }
                .disabled(!model.configuration.rules.contains { $0.id == selection })
                Spacer()
            }
        }
        .padding()
        .sheet(item: $editor) { draft in RuleEditorView(model: model, draft: draft) }
    }

    private func summary(_ rule: Rule) -> String {
        let target: String
        switch rule.action {
        case .showPicker: target = "Ask with picker"
        case .open(let id, _): target = model.targetName(id)
        }
        return "\(conditionSummary(rule.condition)) → \(target)"
    }

    private func badge(_ title: String) -> some View {
        Text(title).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

struct RuleEditorView: View {
    @ObservedObject var model: PreferencesModel
    @State var draft: RuleDraft
    @Environment(\.dismiss) private var dismiss

    private var targets: [Destination] { model.ruleTargets.filter { draft.kind.accepts($0.kind) } }
    private var supportsPrivate: Bool {
        targets.first { $0.id == draft.target }?.supportsPrivateWindow ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(draft.originalRule == nil ? "Add Rule" : "Edit Rule").font(.title2)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
            Form {
                TextField("Name (optional)", text: $draft.name)
                Picker("Condition", selection: $draft.kind) {
                    ForEach(ConditionKind.allCases) { Text($0.title).tag($0) }
                }
                if draft.kind.hasHost {
                    TextField(draft.kind == .pathPattern ? "Host (optional)" : "Host / domain", text: $draft.host)
                }
                if draft.kind.hasValue { TextField(draft.kind.valueLabel, text: $draft.value) }
                if draft.kind == .pathPattern {
                    Text("* matches within one path segment; ** matches across path segments. Leave host empty to match any host.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Action", selection: $draft.target) {
                    Text("Ask with picker").tag(nil as DestinationID?)
                    ForEach(targets) { Text($0.displayName).tag(Optional($0.id)) }
                    if let id = draft.target, !targets.contains(where: { $0.id == id }) {
                        Text("Unavailable: \(id.rawValue)").tag(Optional(id))
                    }
                }
                Toggle("Private window", isOn: $draft.privateWindow).disabled(!supportsPrivate)
                Picker("Match against", selection: $draft.matchTarget) {
                    Text("Processed URL").tag(MatchTarget.processed)
                    Text("Original URL").tag(MatchTarget.original)
                }
                if !draft.isValid {
                    Text("Fill in all required condition fields to save.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(!draft.isValid)
            }
            .padding()
        }
        .frame(width: 520, height: 490)
        .onChange(of: draft.kind) { _, _ in
            if let id = draft.target, !targets.contains(where: { $0.id == id }) { draft.target = nil }
            if !supportsPrivate { draft.privateWindow = false }
        }
        .onChange(of: draft.target) { _, _ in
            if !supportsPrivate { draft.privateWindow = false }
        }
    }

    private func save() {
        guard draft.isValid else { return }
        let rule = draft.rule(supportsPrivate: supportsPrivate)
        model.update { config in
            if let index = config.rules.firstIndex(where: { $0.id == rule.id }) { config.rules[index] = rule }
            else { config.rules.append(rule) }
        }
        dismiss()
    }
}
