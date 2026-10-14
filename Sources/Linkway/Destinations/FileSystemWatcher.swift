import CoreServices
import Foundation

/// FSEvents stream delivering coalesced file-level events on the main queue.
/// The stream's latency doubles as the debounce interval.
final class FileSystemWatcher {
    private final class Context: Sendable {
        let handler: @MainActor @Sendable ([String]) -> Void
        init(handler: @escaping @MainActor @Sendable ([String]) -> Void) { self.handler = handler }
    }

    let paths: [String]
    private let context: Context
    private let stream: FSEventStreamRef

    init?(paths: [String], latency: TimeInterval, handler: @escaping @MainActor @Sendable ([String]) -> Void) {
        guard !paths.isEmpty else { return nil }
        let context = Context(handler: handler)
        var streamContext = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(context).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let context = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()
            let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            let paths = (array as? [String]) ?? []
            MainActor.assumeIsolated { context.handler(paths) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &streamContext, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return nil }

        self.paths = paths
        self.context = context
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
