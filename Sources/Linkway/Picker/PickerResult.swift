import Foundation
import LinkwayCore

enum PickerResult: Sendable {
    case open(LaunchRequest, remember: Bool)
    case copied(URL)
    case dismissed
}
