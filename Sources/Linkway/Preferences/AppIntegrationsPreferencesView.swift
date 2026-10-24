import LinkwayCore
import SwiftUI

struct AppIntegrationsPreferencesView: View {
    @ObservedObject var model: PreferencesModel

    private var detectedAdapters: [DeepLinkAdapter] {
        DeepLinkCatalog.adapters.filter { adapter in
            model.pickerEntries.contains { $0.kind == .app && adapter.appBundleIDs.contains($0.id.bundleID) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installed apps appear before browsers for supported links. Rules can target enabled integrations.")
                .font(.caption).foregroundStyle(.secondary)
            List(detectedAdapters) { adapter in
                Toggle(adapter.displayName, isOn: Binding(get: {
                    !model.configuration.disabledAppAdapters.contains(adapter.id.rawValue)
                }, set: { enabled in
                    model.update {
                        $0.disabledAppAdapters.removeAll { $0 == adapter.id.rawValue }
                        if !enabled { $0.disabledAppAdapters.append(adapter.id.rawValue) }
                    }
                }))
            }
            .overlay {
                if detectedAdapters.isEmpty { Text("No supported desktop apps found.").foregroundStyle(.secondary) }
            }
        }
        .padding()
    }
}
