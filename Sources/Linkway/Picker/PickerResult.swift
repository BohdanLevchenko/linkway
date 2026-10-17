import Foundation
import LinkwayCore

enum PickerResult: Sendable {
    /// `remember` is the scope the user chose to save this choice for, or nil.
    case open(LaunchRequest, remember: RememberTarget?)
    case copied(URL)
    case dismissed
}
