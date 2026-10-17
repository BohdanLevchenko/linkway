import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let model: PreferencesModel

    init(router: LinkRouter) {
        model = PreferencesModel(router: router)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Linkway Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: PreferencesView(model: model))
        window.minSize = NSSize(width: 640, height: 460)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        model.refreshLoginStatus()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        TabView {
            GeneralPreferencesView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            DestinationPreferencesView(model: model, kind: .browser)
                .tabItem { Label("Browsers", systemImage: "globe") }
            DestinationPreferencesView(model: model, kind: .mailClient)
                .tabItem { Label("Mail", systemImage: "envelope") }
            RulesPreferencesView(model: model)
                .tabItem { Label("Rules", systemImage: "list.bullet") }
            RoutingTestView(model: model)
                .tabItem { Label("Test", systemImage: "checkmark.circle") }
        }
        .padding(16)
        .alert("Configuration Error", isPresented: Binding(
            get: { model.fileError != nil }, set: { if !$0 { model.fileError = nil } }
        )) {
            Button("OK", role: .cancel) { model.fileError = nil }
        } message: { Text(model.fileError ?? "") }
    }
}
