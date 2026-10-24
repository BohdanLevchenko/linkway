import LinkwayCore
import SwiftUI

struct DestinationPreferencesView: View {
    @ObservedObject var model: PreferencesModel
    let kind: DestinationKind

    private var fallback: Binding<DestinationID?> {
        Binding(get: {
            let policy = kind == .mailClient ? model.configuration.fallbacks.mail : model.configuration.fallbacks.web
            if case .open(let id) = policy { return id }
            return nil
        }, set: { id in
            model.update {
                let policy = id.map(FallbackPolicy.open) ?? .showPicker
                if kind == .mailClient { $0.fallbacks.mail = policy }
                else { $0.fallbacks.web = policy }
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorites appear first in the picker. Drag rows to reorder within favorites or other destinations.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                if kind == .mailClient {
                    WebmailPreferencesView(model: model)
                }
                ForEach(model.destinations(kind: kind)) { destination in
                    row(destination)
                }
                .onMove { model.moveDestinations(kind: kind, from: $0, to: $1) }
            }
            .overlay {
                if kind != .mailClient && model.destinations(kind: kind).isEmpty { Text("No destinations found.").foregroundStyle(.secondary) }
            }
            Picker("When no rule matches", selection: fallback) {
                Text("Ask with picker").tag(nil as DestinationID?)
                ForEach(model.ruleTargets.filter { $0.kind == kind }) {
                    Text($0.displayName).tag(Optional($0.id))
                }
                if let id = fallback.wrappedValue,
                   !model.ruleTargets.contains(where: { $0.id == id && $0.kind == kind }) {
                    Text("Unavailable: \(id.rawValue)").tag(Optional(id))
                }
            }
        }
        .padding()
    }

    private func row(_ destination: Destination) -> some View {
        let hidden = model.configuration.hiddenDestinations.contains(destination.id)
        let favorite = model.configuration.favoriteDestinations.contains(destination.id)
        return HStack {
            Image(nsImage: model.router.icon(for: destination)).resizable().frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text(destination.displayName).frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Show in picker", isOn: Binding(get: { !hidden }, set: { show in
                model.update {
                    if show { $0.hiddenDestinations.remove(destination.id) }
                    else { $0.hiddenDestinations.insert(destination.id) }
                }
            }))
            .toggleStyle(.checkbox)
            Button {
                model.update {
                    if favorite { $0.favoriteDestinations.removeAll { $0 == destination.id } }
                    else { $0.favoriteDestinations.append(destination.id) }
                }
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(favorite ? "Unfavorite" : "Favorite") \(destination.displayName)")
            .help(favorite ? "Remove from favorites" : "Add to favorites")
        }
        .opacity(hidden ? 0.5 : 1)
        .padding(.vertical, 3)
    }
}
