import LinkwayCore
import ServiceManagement
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var handlers: DefaultHandlers
    @ObservedObject var preferences: PreferencesModel
    let openPreferences: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step == model.step ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count): \(model.step.title)")

            Text(model.step.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { stepContent }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack {
                if model.step != .welcome {
                    Button("Back") { model.step = model.step.previous }
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(primaryTitle) {
                    if model.step == .done { finish() }
                    else {
                        model.refresh()
                        model.step = model.step.next
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 440)
    }

    private var primaryTitle: String {
        if model.step == .done { return "Finish" }
        if model.step == .mail && !model.mailIsDefault { return "Skip" }
        return "Continue"
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .welcome:
            Text("Linkway sits between links and browsers: it asks where each link should open and can remember your choice per site or path. It works locally with no account.")
        case .browser:
            handlerSetup(role: .browser, name: model.browserName, isDefault: model.browserIsDefault,
                         message: model.browserMessage)
        case .mail:
            Text("Optionally let Linkway handle mail links. It then asks which mail app to use.")
            handlerSetup(role: .mail, name: model.mailName, isDefault: model.mailIsDefault,
                         message: model.mailMessage)
        case .login:
            Text("Have Linkway ready when you sign in. You can change this later in Settings.")
            Toggle("Launch at login", isOn: Binding(
                get: { preferences.loginStatus == .enabled || preferences.loginStatus == .requiresApproval },
                set: { preferences.setLaunchAtLogin($0) }
            ))
            .disabled(preferences.loginOperationInProgress)
            Text(preferences.loginStatusText).font(.callout).foregroundStyle(.secondary)
            if preferences.loginStatus == .requiresApproval {
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = preferences.loginError { Text(error).foregroundStyle(.red) }
        case .done:
            Text(forcePickerTip)
            Text("In the picker, digits pick. ⌘R remembers the choice for a site or path.")
            Text("Settings… in the menu bar edits rules.")
            Text("To stop using Linkway: System Settings → Desktop & Dock → Default web browser.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Open Settings…", action: openPreferences)
        }
    }

    private func handlerSetup(role: HandlerRole, name: String, isDefault: Bool, message: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current handler: \(name)")
            Button(role == .browser ? "Make Linkway Default Browser" : "Make Linkway Default Mail Handler") {
                model.makeDefault(role)
            }
            .disabled(handlers.isWorking || isDefault)
            Text("macOS will ask you to confirm the change.")
                .font(.caption).foregroundStyle(.secondary)
            if isDefault {
                Label(role == .browser ? "Linkway is your default browser" : "Linkway handles your mail links",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let message {
                Text(message).font(.callout)
            }
            if handlers.isWorking {
                Text("Waiting for macOS confirmation…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var forcePickerTip: String {
        let key: String
        switch preferences.configuration.forcePickerModifier {
        case .option: key = "⌥ (Option)"
        case .command: key = "⌘ (Command)"
        case .control: key = "⌃ (Control)"
        case .shift: key = "⇧ (Shift)"
        case .none: return "Set a force-picker key in Settings to always show the picker when opening a link."
        }
        return "Hold \(key) when clicking a link to always get the picker."
    }
}
