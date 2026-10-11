import Foundation

public enum ModifierKey: String, Codable, Sendable, Hashable {
    case option
    case command
    case control
    case shift
    case none
}

public struct LinkwayConfiguration: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var rules: [Rule]
    public var fallbacks: FallbackPolicies
    public var destinationOrder: [DestinationID]
    public var hiddenDestinations: Set<DestinationID>
    public var favoriteDestinations: [DestinationID]
    public var forcePickerModifier: ModifierKey

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        rules: [Rule] = [], fallbacks: FallbackPolicies = FallbackPolicies(),
        destinationOrder: [DestinationID] = [], hiddenDestinations: Set<DestinationID> = [],
        favoriteDestinations: [DestinationID] = [], forcePickerModifier: ModifierKey = .option
    ) {
        self.schemaVersion = schemaVersion
        self.rules = rules
        self.fallbacks = fallbacks
        self.destinationOrder = destinationOrder
        self.hiddenDestinations = hiddenDestinations
        self.favoriteDestinations = favoriteDestinations
        self.forcePickerModifier = forcePickerModifier
    }

    public static let `default` = LinkwayConfiguration()
}
