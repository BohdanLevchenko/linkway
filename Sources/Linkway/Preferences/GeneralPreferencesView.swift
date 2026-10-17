import AppKit
import ServiceManagement
import SwiftUI
import LinkwayCore

struct GeneralPreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        Form {
            Section {
                Picker("Force picker modifier", selection: model.binding(to: \.forcePickerModifier)) {
                    Text("Option").tag(ModifierKey.option)
                    Text("Command").tag(ModifierKey.command)
                    Text("Control").tag(ModifierKey.control)
                    Text("Shift").tag(ModifierKey.shift)
                    Text("None").tag(ModifierKey.none)
                }
                Text("Hold this key when opening a link to choose a destination, even when a rule matches.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .disabled(model.loginOperationInProgress)
                Text(model.loginStatusText).font(.caption).foregroundStyle(.secondary)
                if model.loginStatus == .requiresApproval {
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let error = model.loginError { Text(error).foregroundStyle(.red) }
            }
            Section("Configuration") {
                HStack {
                    Button("Import…") { model.importFile() }
                    Button("Export…") { model.exportFile() }
                }
                .disabled(model.fileOperationInProgress)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLoginStatus()
        }
    }
}
