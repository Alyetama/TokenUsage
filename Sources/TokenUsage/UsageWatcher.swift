import Foundation
import CoreServices

/// Watches the agent data directories with FSEvents and fires `onChange`
/// (coalesced, on the main queue) whenever any log file underneath them
/// changes. This makes updates near-instant instead of waiting for the
/// fallback poll timer.
final class UsageWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    /// Fails (returns nil) when none of the paths exist yet — the fallback
    /// poll timer still covers agents installed after launch.
    init?(paths: [String], onChange: @escaping () -> Void) {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return nil }
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<UsageWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,  // coalesce bursts of writes into one event every ~2s
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
