import Foundation
import LinkwayCore

enum PickerResult: Sendable {
    case open(LaunchRequest)
    case copied(URL)
    case dismissed
}
