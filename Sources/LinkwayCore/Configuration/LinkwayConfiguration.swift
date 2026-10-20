import Foundation

public enum ModifierKey: String, Codable, Sendable, Hashable {
    case option
    case command
    case control
    case shift
    case none
}

public enum PickerStyle: String, Codable, Sendable, Hashable, CaseIterable {
    case tiles, list
}

public struct LinkwayConfiguration: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1
    public var urlProcessing: URLProcessingSettings
    public var schemaVersion: Int
    public var rules: [Rule]
    public var fallbacks: FallbackPolicies
    public var destinationOrder: [DestinationID]
    public var hiddenDestinations: Set<DestinationID>
    public var favoriteDestinations: [DestinationID]
    public var pickerStyle: PickerStyle
    public var forcePickerModifier: ModifierKey

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        rules: [Rule] = [], fallbacks: FallbackPolicies = FallbackPolicies(),
        destinationOrder: [DestinationID] = [], hiddenDestinations: Set<DestinationID> = [],
        favoriteDestinations: [DestinationID] = [], forcePickerModifier: ModifierKey = .option,
        pickerStyle: PickerStyle = .tiles, urlProcessing: URLProcessingSettings = .init()
    ) {
        self.urlProcessing = urlProcessing
        self.pickerStyle = pickerStyle
        self.schemaVersion = schemaVersion
        self.rules = rules
        self.fallbacks = fallbacks
        self.destinationOrder = destinationOrder
        self.hiddenDestinations = hiddenDestinations
        self.favoriteDestinations = favoriteDestinations
        self.forcePickerModifier = forcePickerModifier
    }

    enum CodingKeys: String, CodingKey {
        case urlProcessing
        case schemaVersion, rules, fallbacks, destinationOrder, hiddenDestinations
        case favoriteDestinations, forcePickerModifier, pickerStyle
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        urlProcessing = try values.decodeIfPresent(URLProcessingSettings.self, forKey: .urlProcessing) ?? .init()
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        rules = try values.decode([Rule].self, forKey: .rules)
        fallbacks = try values.decode(FallbackPolicies.self, forKey: .fallbacks)
        destinationOrder = try values.decode([DestinationID].self, forKey: .destinationOrder)
        hiddenDestinations = try values.decode(Set<DestinationID>.self, forKey: .hiddenDestinations)
        favoriteDestinations = try values.decode([DestinationID].self, forKey: .favoriteDestinations)
        forcePickerModifier = try values.decode(ModifierKey.self, forKey: .forcePickerModifier)
        pickerStyle = try values.decodeIfPresent(PickerStyle.self, forKey: .pickerStyle) ?? .tiles
    }

    public static let `default` = LinkwayConfiguration()
}
