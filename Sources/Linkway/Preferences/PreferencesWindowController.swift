import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    private static let defaultSize = NSSize(width: 720, height: 520)
    private static let minimumSize = NSSize(width: 640, height: 460)
    private let model: PreferencesModel

    init(router: LinkRouter, handlers: DefaultHandlers, showWelcomeGuide: @escaping () -> Void) {
        model = PreferencesModel(router: router)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Linkway Settings"
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: PreferencesView(
            model: model, handlers: handlers, showWelcomeGuide: showWelcomeGuide
        ))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(Self.defaultSize)
        window.contentMinSize = Self.minimumSize
        window.setFrameAutosaveName("LinkwaySettings")
        if !window.setFrameUsingName("LinkwaySettings") { window.center() }
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
    let handlers: DefaultHandlers
    let showWelcomeGuide: () -> Void

    var body: some View {
        TabView {
            GeneralPreferencesView(model: model, handlers: handlers, showWelcomeGuide: showWelcomeGuide)
                .tabItem { Label("General", systemImage: "gearshape") }
            DestinationPreferencesView(model: model, kind: .browser)
                .tabItem { Label("Browsers", systemImage: "globe") }
            DestinationPreferencesView(model: model, kind: .mailClient)
                .tabItem { Label("Mail", systemImage: "envelope") }
            AppIntegrationsPreferencesView(model: model)
                .tabItem { Label("Apps", systemImage: "app") }
            LinksPreferencesView(model: model)
                .tabItem { Label("Links", systemImage: "link") }
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
