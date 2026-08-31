import Foundation

/// Watches one file for writes by other programs and reports them on the
/// main actor, debounced. Most editors save atomically by replacing the
/// inode, so delete and rename events re-open the path and keep watching
/// the new file.
@MainActor
final class FileWatcher {
    static let debounce: TimeInterval = 0.1
    static let rearmDelay: TimeInterval = 0.05

    private let url: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pendingChange: Task<Void, Never>?
    private var cancelled = false

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        watch()
    }

    /// Stops watching and closes the file descriptor. Must be called before
    /// the watcher is released; there is no isolated deinit to do it.
    func cancel() {
        cancelled = true
        pendingChange?.cancel()
        pendingChange = nil
        source?.cancel()
        source = nil
    }

    private func watch() {
        guard !cancelled else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // Mid-replace the path can briefly not exist; try again shortly.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.rearmDelay))
                self?.watch()
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handleEvent() }
        }
        source.setCancelHandler { close(descriptor) }
        source.activate()
        self.source = source
    }

    private func handleEvent() {
        guard let source, !cancelled else { return }
        if !source.data.intersection([.delete, .rename]).isEmpty {
            source.cancel()
            self.source = nil
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.rearmDelay))
                self?.watch()
            }
        }
        pendingChange?.cancel()
        pendingChange = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.debounce))
            guard !Task.isCancelled, let self, !self.cancelled else { return }
            self.onChange()
        }
    }
}
