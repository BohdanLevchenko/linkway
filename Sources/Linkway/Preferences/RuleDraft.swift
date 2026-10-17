import Foundation
import LinkwayCore

enum ConditionKind: String, CaseIterable, Identifiable {
    case hostExact, hostIncludingSubdomains, urlPrefix, pathPattern, sitePath, sourceApp, mailRecipientDomain

    var id: Self { self }
    var title: String {
        switch self {
        case .hostExact: "Exact host"
        case .hostIncludingSubdomains: "Host and subdomains"
        case .urlPrefix: "URL prefix"
        case .pathPattern: "Path pattern"
        case .sitePath: "Site and path"
        case .sourceApp: "Source app"
        case .mailRecipientDomain: "Mail recipient domain"
        }
    }

    init(_ condition: RuleCondition) {
        switch condition {
        case .hostExact: self = .hostExact
        case .hostIncludingSubdomains: self = .hostIncludingSubdomains
        case .urlPrefix: self = .urlPrefix
        case .pathPattern: self = .pathPattern
        case .sitePath: self = .sitePath
        case .sourceApp: self = .sourceApp
        case .mailRecipientDomain: self = .mailRecipientDomain
        }
    }

    func condition(host: String, value: String) -> RuleCondition {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = value.hasPrefix("/") ? value : "/" + value
        switch self {
        case .hostExact: return .hostExact(host)
        case .hostIncludingSubdomains: return .hostIncludingSubdomains(host)
        case .urlPrefix: return .urlPrefix(value)
        case .pathPattern: return .pathPattern(host: host.isEmpty ? nil : host, pattern: path)
        case .sitePath: return .sitePath(host: host, pathPrefix: path)
        case .sourceApp: return .sourceApp(bundleID: value)
        case .mailRecipientDomain: return .mailRecipientDomain(host)
        }
    }

    var hasHost: Bool {
        switch self {
        case .hostExact, .hostIncludingSubdomains, .pathPattern, .sitePath, .mailRecipientDomain: true
        case .urlPrefix, .sourceApp: false
        }
    }

    var hasValue: Bool {
        switch self {
        case .pathPattern, .sitePath, .urlPrefix, .sourceApp: true
        default: false
        }
    }

    var valueLabel: String {
        switch self {
        case .pathPattern: "Pattern"
        case .sitePath: "Path prefix"
        case .sourceApp: "Bundle ID"
        default: "URL prefix"
        }
    }

    func accepts(_ kind: DestinationKind) -> Bool {
        switch self {
        case .sourceApp: true
        case .mailRecipientDomain: kind == .mailClient
        default: kind == .browser
        }
    }
}

func conditionSummary(_ condition: RuleCondition) -> String {
    switch condition {
    case .hostExact(let host): host
    case .hostIncludingSubdomains(let host): "\(host) (including subdomains)"
    case .urlPrefix(let prefix): prefix
    case .pathPattern(let host, let pattern): "\(host ?? "Any host") \(pattern)"
    case .sitePath(let host, let path): "\(host)\(path)"
    case .sourceApp(let bundleID): "From \(bundleID)"
    case .mailRecipientDomain(let domain): "Mail to @\(domain)"
    }
}

struct RuleDraft: Identifiable {
    let id: UUID
    var name: String
    var kind: ConditionKind
    var host = ""
    var value = ""
    var target: DestinationID?
    var privateWindow = false
    var matchTarget: MatchTarget
    let isEnabled: Bool
    let originalRule: Rule?

    init(rule: Rule? = nil) {
        originalRule = rule
        id = rule?.id ?? UUID()
        name = rule?.name ?? ""
        kind = rule.map { ConditionKind($0.condition) } ?? .hostExact
        matchTarget = rule?.matchTarget ?? .processed
        isEnabled = rule?.isEnabled ?? true
        guard let rule else { return }
        switch rule.condition {
        case .hostExact(let h), .hostIncludingSubdomains(let h), .mailRecipientDomain(let h): host = h
        case .urlPrefix(let v), .sourceApp(let v): value = v
        case .pathPattern(let h, let v): host = h ?? ""; value = v
        case .sitePath(let h, let v): host = h; value = v
        }
        if case .open(let id, let isPrivate) = rule.action { target = id; privateWindow = isPrivate }
    }

    var isValid: Bool {
        (!kind.hasHost || kind == .pathPattern || !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (!kind.hasValue || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func rule(supportsPrivate: Bool) -> Rule {
        let condition = kind.condition(host: host, value: value)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Rule(
            id: id, name: trimmedName.isEmpty ? conditionSummary(condition) : trimmedName,
            isEnabled: isEnabled, condition: condition,
            action: target.map { .open($0, privateWindow: privateWindow && supportsPrivate) } ?? .showPicker,
            matchTarget: matchTarget, origin: .manual
        )
    }
}
