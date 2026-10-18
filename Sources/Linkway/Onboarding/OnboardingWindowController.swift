import AppKit
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, browser, mail, login, done

    var title: String {
        switch self {
        case .welcome: "Welcome to Linkway"
        case .browser: "Default browser"
        case .mail: "Mail links (optional)"
        case .login: "Launch at login (optional)"
        case .done: "You're ready"
        }
    }

    var next: Self { Self(rawValue: rawValue + 1) ?? self }
    var previous: Self { Self(rawValue: rawValue - 1) ?? self }
}

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let model: OnboardingModel

    init(handlers: DefaultHandlers, router: LinkRouter, openPreferences: @escaping () -> Void) {
        model = OnboardingModel(handlers: handlers, preferences: PreferencesModel(router: router))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "Welcome to Linkway"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: OnboardingView(
            model: model, handlers: handlers, preferences: model.preferences,
            openPreferences: openPreferences, finish: { [weak self] in self?.finish() }
        ))
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        model.step = .welcome
        model.resetMessages()
        model.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) { model.refresh() }

    func windowWillClose(_ notification: Notification) {
        if model.step == .done { UserDefaults.standard.set(true, forKey: "onboardingCompleted") }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        close()
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step = OnboardingStep.welcome
    @Published private(set) var browserIsDefault = false
    @Published private(set) var mailIsDefault = false
    @Published private(set) var browserName = "None"
    @Published private(set) var mailName = "None"
    @Published private(set) var browserMessage: String?
    @Published private(set) var mailMessage: String?
    let handlers: DefaultHandlers
    let preferences: PreferencesModel

    init(handlers: DefaultHandlers, preferences: PreferencesModel) {
        self.handlers = handlers
        self.preferences = preferences
    }

    func refresh() {
        browserIsDefault = handlers.isDefault(.browser)
        mailIsDefault = handlers.isDefault(.mail)
        browserName = handlers.currentHandlerName(.browser)
        mailName = handlers.currentHandlerName(.mail)
        preferences.refreshLoginStatus()
    }

    func resetMessages() {
        browserMessage = nil
        mailMessage = nil
    }

    func makeDefault(_ role: HandlerRole) {
        guard !handlers.isWorking else { return }
        Task {
            let outcome = await handlers.makeDefault(role)
            refresh()
            let message: String?
            switch outcome {
            case .alreadyDefault, .changed: message = nil
            case .declined: message = "macOS kept the current default. You can continue and change it later."
            case .failed(let reason): message = "Could not change the default: \(reason)"
            }
            switch role {
            case .browser: browserMessage = message
            case .mail: mailMessage = message
            }
        }
    }
}
