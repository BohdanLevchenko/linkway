import LinkwayCore
import SwiftUI

struct LinksPreferencesView: View {
    @ObservedObject var model: PreferencesModel
    var body: some View {
        Form {
            Section("Tracking cleaner") {
                Toggle("Remove tracking parameters", isOn: model.binding(to: \.urlProcessing.cleanTracking))
                Toggle("Unwrap redirect links (Google, Facebook, Outlook Safe Links…)",
                       isOn: model.binding(to: \.urlProcessing.unwrapRedirectLinks))
                ParameterList(title: "Extra parameters", prompt: "Parameter name or prefix*",
                              values: model.binding(to: \.urlProcessing.extraTrackingParameters))
                ParameterList(title: "Kept parameters", prompt: "Parameter name or prefix*",
                              values: model.binding(to: \.urlProcessing.keptParameters))
                ParameterList(title: "Excluded sites", prompt: "example.com",
                              values: model.binding(to: \.urlProcessing.cleanerExcludedHosts))
            }
            Section("Short links") {
                Toggle("Expand short links before routing", isOn: model.binding(to: \.urlProcessing.expandShortLinks))
                Text("Linkway asks the shortener where the link goes, without cookies. The shortener counts this as a click. Links to other sites never wait.")
                    .font(.caption).foregroundStyle(.secondary)
                ParameterList(title: "Shortener hosts", prompt: "short.example.com",
                              values: model.binding(to: \.urlProcessing.shortenerHosts))
                Button("Restore Defaults") { model.update { $0.urlProcessing.shortenerHosts = URLProcessingSettings.defaultShortenerHosts } }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ParameterList: View {
    let title: String
    let prompt: String
    @Binding var values: [String]
    @State private var addition = ""
    var body: some View {
        DisclosureGroup("\(title) (\(values.count))") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    HStack {
                        Text(value).textSelection(.enabled)
                        Spacer()
                        Button { values.remove(at: index) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("Remove " + value)
                    }
                }
                HStack {
                    TextField(prompt, text: $addition).onSubmit(add)
                        .accessibilityLabel("Add to " + title)
                    Button("Add", action: add).disabled(addition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(.vertical, 6)
        }
    }
    private func add() {
        let value = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, !values.contains(value) { values.append(value) }
        addition = ""
    }
}
