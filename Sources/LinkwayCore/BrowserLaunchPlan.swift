import Foundation

public enum BrowserRunningState: Sendable {
    case stopped
    /// Includes both the target profile and another profile running.
    case running
}

public struct BrowserLaunchPlan: Sendable, Equatable {
    public enum Delivery: Sendable {
        case launchApplication
        case forward
    }

    public let arguments: [String]
    public let delivery: Delivery

    public init(arguments: [String], runningState: BrowserRunningState) {
        self.arguments = arguments
        delivery = runningState == .stopped ? .launchApplication : .forward
    }

    public static func firefox(
        url: URL, profilePath: URL?, privateWindow: Bool, runningState: BrowserRunningState
    ) -> BrowserLaunchPlan {
        var arguments: [String] = []
        if let profilePath {
            arguments += ["-profile", profilePath.standardizedFileURL.path]
        }
        if privateWindow { arguments.append("-private-window") }
        return BrowserLaunchPlan(arguments: arguments + [url.absoluteString], runningState: runningState)
    }
}
