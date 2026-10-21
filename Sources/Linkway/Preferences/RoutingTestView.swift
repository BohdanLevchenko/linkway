import Foundation
import LinkwayCore
import SwiftUI

struct RoutingTestView: View {
    @ObservedObject var model: PreferencesModel
    @State private var input = ""
    @State private var sender = ""
    @State private var explanation: RoutingExplanation?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("URL", text: $input).onSubmit { test() }
                .accessibilityLabel("URL to test")
            TextField("Sender app bundle ID (optional)", text: $sender).onSubmit { test() }
            Button("Test", action: test).keyboardShortcut(.return, modifiers: [])
            Text("Tests the current rules with offline URL cleaning, without opening the link.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            if let explanation {
                if let processed = explanation.processedURL, processed.absoluteString != input.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Text("Processed: " + processed.absoluteString).font(.caption).textSelection(.enabled)
                    if !explanation.removedParameters.isEmpty {
                        Text("Removed: " + explanation.removedParameters.joined(separator: ", ")).font(.caption)
                    }
                }
                if explanation.wouldExpandShortLink {
                    Text("Short link: would be expanded when opened").font(.caption).foregroundStyle(.secondary)
                }
                Text(decisionText(explanation.decision)).font(.headline).textSelection(.enabled)
                List(Array(explanation.evaluations.enumerated()), id: \.offset) { _, evaluation in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(evaluation.matched ? "✓" : "✗") \(ruleName(evaluation.ruleID))")
                        Text(evaluation.reason).font(.caption).foregroundStyle(.secondary)
                        Text(evaluation.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                    }
                    .textSelection(.enabled)
                }
            } else { Spacer() }
        }
        .padding()
        .onChange(of: input) { _, _ in explanation = nil; error = nil }
        .onChange(of: sender) { _, _ in explanation = nil; error = nil }
        .onChange(of: model.configuration) { _, _ in explanation = nil }
        .onChange(of: model.availableIDs) { _, _ in explanation = nil }
    }

    private func ruleName(_ id: UUID) -> String {
        model.configuration.rules.first { $0.id == id }?.name ?? "Unknown rule"
    }

    private func test() {
        explanation = nil
        error = nil
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }),
              let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              (!(scheme.lowercased() == "http" || scheme.lowercased() == "https") || !(components.host ?? "").isEmpty)
        else {
            error = "Enter a valid, complete URL, such as https://github.com/antiwork."
            return
        }
        let bundleID = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        explanation = model.router.explain(url, senderBundleID: bundleID.isEmpty ? nil : bundleID)
    }

    private func decisionText(_ decision: RoutingDecision) -> String {
        switch decision {
        case .launch(let request, _):
            return "Opens in \(model.targetName(request.destination))\(request.privateWindow ? " · Private" : "")"
        case .showPicker(let reason):
            switch reason {
            case .noMatch:
                let kind = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.lowercased()
                let fallback: FallbackPolicy = kind == "mailto" ? model.configuration.fallbacks.mail :
                    (["http", "https"].contains(kind ?? "") ? model.configuration.fallbacks.web : .showPicker)
                if case .open(let id) = fallback, !model.availableIDs.contains(id) {
                    return "Shows picker: target unavailable"
                }
                return "Shows picker: no rule matched"
            case .forcedByUser: return "Shows picker: forced by user"
            case .ruleRequestsPicker: return "Shows picker: rule requests picker"
            case .ruleTargetUnavailable: return "Shows picker: target unavailable"
            }
        }
    }
}
