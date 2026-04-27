import Foundation
@preconcurrency import CoreServices

final class AppCatalogWatcher {
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "vish.app-catalog-watcher", qos: .utility)
    private var pending: DispatchWorkItem?
    private var stream: FSEventStreamRef?

    init(paths: [String], onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        stream = FSEventStreamCreate(
            nil,
            { _, contextInfo, _, _, _, _ in
                guard let contextInfo else { return }
                Unmanaged<AppCatalogWatcher>
                    .fromOpaque(contextInfo)
                    .takeUnretainedValue()
                    .scheduleRefresh()
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )

        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        pending?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func scheduleRefresh() {
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
