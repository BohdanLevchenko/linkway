import LinkwayCore
import SwiftUI

struct WebmailPreferencesView: View {
    @ObservedObject var model: PreferencesModel
    @State private var draft: WebmailAccount?

    private var browsers: [Destination] { model.ruleTargets.filter { $0.kind == .browser } }

    var body: some View {
        GroupBox("Webmail") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.configuration.webmailAccounts) { account in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.displayName)
                            Text("\(account.provider.name) · \(model.targetName(account.browser))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { draft = account }
                            .accessibilityLabel("Edit \(account.displayName)")
                        Button("Remove", role: .destructive) {
                            model.update { $0.webmailAccounts.removeAll { $0.id == account.id } }
                            if draft?.id == account.id { draft = nil }
                        }
                        .accessibilityLabel("Remove \(account.displayName)")
                    }
                }
                if let account = draft {
                    WebmailAccountEditor(account: account, browsers: browsers) { saved in
                        if let saved {
                            model.update { configuration in
                                if let index = configuration.webmailAccounts.firstIndex(where: { $0.id == saved.id }) {
                                    configuration.webmailAccounts[index] = saved
                                } else { configuration.webmailAccounts.append(saved) }
                            }
                        }
                        draft = nil
                    }
                    .id(account.id)
                } else {
                    Button("Add Webmail Account") {
                        guard let browser = browsers.first else { return }
                        draft = WebmailAccount(provider: .gmail, displayName: "", browser: browser.id)
                    }
                    .disabled(browsers.isEmpty)
                    if browsers.isEmpty {
                        Text("Install a browser to add a webmail account.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
        }
    }
}

private struct WebmailAccountEditor: View {
    @State var account: WebmailAccount
    let browsers: [Destination]
    let finish: (WebmailAccount?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Provider", selection: $account.provider) {
                ForEach(WebmailProvider.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            TextField("Display name", text: $account.displayName)
            if account.provider == .gmail {
                TextField("Account email (optional)", text: Binding(
                    get: { account.account ?? "" }, set: { account.account = $0.isEmpty ? nil : $0 }
                ))
            }
            Picker("Browser / profile", selection: $account.browser) {
                ForEach(browsers) { Text($0.displayName).tag($0.id) }
                if !browsers.contains(where: { $0.id == account.browser }) {
                    Text("Unavailable: \(account.browser.rawValue)").tag(account.browser)
                }
            }
            HStack {
                Button("Cancel") { finish(nil) }
                Button("Save") {
                    var saved = account
                    saved.displayName = saved.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if saved.provider != .gmail { saved.account = nil }
                    finish(saved)
                }
                .disabled(account.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || !browsers.contains(where: { $0.id == account.browser }))
            }
        }
    }
}
