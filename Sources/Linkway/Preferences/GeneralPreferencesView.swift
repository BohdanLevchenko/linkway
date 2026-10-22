import AppKit
import ServiceManagement
import SwiftUI
import LinkwayCore

private struct HandlerRowID: Hashable {
    let role: HandlerRole
    let revision: Int
}

struct GeneralPreferencesView: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var handlers: DefaultHandlers
    let showWelcomeGuide: () -> Void
    @State private var handlerStatusRevision = 0

    var body: some View {
        Form {
            Section("Default apps") {
                defaultAppRow("Web links", role: .browser)
                defaultAppRow("Mail links", role: .mail)
                Text("macOS asks to confirm. To stop using Linkway, pick another browser in System Settings → Desktop & Dock.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Show Welcome Guide…", action: showWelcomeGuide)
            }
            Section {
                Picker("Picker style", selection: model.binding(to: \.pickerStyle)) {
                    Text("Tiles").tag(PickerStyle.tiles)
                    Text("List").tag(PickerStyle.list)
                }
                .pickerStyle(.segmented)
                Text("Tiles show up to 6 destinations; favorites come first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
            Section("Scripting") {
                scriptingExample("Terminal", code: #"open "linkway://open/https://example.com""#)
                scriptingExample("AppleScript", code: #"open location "linkway://open/https://example.com""#)
                DisclosureGroup("More examples") {
                    scriptingExample("JavaScript", code: #"window.location.href = "linkway://open/https://example.com";"#)
                    scriptingExample("Swift", code: #"NSWorkspace.shared.open(URL(string: "linkway://open/https://example.com")!)"#)
                }
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
        .onAppear {
            model.refreshLoginStatus()
            handlerStatusRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLoginStatus()
            handlerStatusRevision += 1
        }
    }

    private func scriptingExample(_ title: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .accessibilityLabel("Copy \(title) example")
            }
            Text(code).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func defaultAppRow(_ title: String, role: HandlerRole) -> some View {
        LabeledContent(title) {
            if handlers.isDefault(role) {
                Label("Linkway", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                HStack {
                    Text(handlers.currentHandlerName(role)).foregroundStyle(.secondary)
                    Button("Use Linkway") {
                        Task {
                            _ = await handlers.makeDefault(role)
                            handlerStatusRevision += 1
                        }
                    }
                    .disabled(handlers.isWorking)
                }
            }
        }
        .id(HandlerRowID(role: role, revision: handlerStatusRevision))
    }
}
