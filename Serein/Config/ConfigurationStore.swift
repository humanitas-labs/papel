import Foundation

/// Owns the live configuration: loads the file, writes the template when it
/// is missing, and reloads whenever the file changes on disk. Every window
/// reads `current` and listens for `Configuration.didChangeNotification`.
@MainActor
final class ConfigurationStore: ObservableObject {
    static let shared = ConfigurationStore(fileURL: defaultFileURL)

    /// `$XDG_CONFIG_HOME/serein/config`, or `~/.config/serein/config`.
    static var defaultFileURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("serein", isDirectory: true).appendingPathComponent("config")
    }

    @Published private(set) var current = Configuration()
    /// Names of the saved presets, sorted, refreshed whenever the presets
    /// directory changes.
    @Published private(set) var presets: [String] = []
    let fileURL: URL

    /// `presets/` beside the config file; one file per preset in the same
    /// `key = value` format, named after the preset.
    var presetsDirectoryURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("presets", isDirectory: true)
    }

    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var presetsSource: DispatchSourceFileSystemObject?
    private var reloadTask: Task<Void, Never>?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Creates the config file from the template if absent, loads it, and
    /// starts watching. Safe to call more than once.
    func start() {
        ensureFileExists()
        reload()
        loadPresets()
        watch()
    }

    // MARK: - Presets

    /// A preset name is a file name: non-empty, no path separators.
    static func isValidPresetName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains("/") && !trimmed.hasPrefix(".")
    }

    func presetURL(named name: String) -> URL {
        presetsDirectoryURL.appendingPathComponent(name.trimmingCharacters(in: .whitespaces))
    }

    func loadPresets() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: presetsDirectoryURL.path)) ?? []
        presets = names
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func preset(named name: String) -> Configuration? {
        guard let text = try? String(contentsOf: presetURL(named: name), encoding: .utf8) else { return nil }
        return Configuration.parse(text)
    }

    /// The saved preset whose values equal the live configuration, if any.
    var matchingPreset: String? {
        presets.first { preset(named: $0) == current }
    }

    /// Saves `configuration` (the live one by default) under `name`,
    /// replacing any preset of that name.
    @discardableResult
    func savePreset(named name: String, _ configuration: Configuration? = nil) -> Bool {
        guard Self.isValidPresetName(name) else { return false }
        let target = configuration ?? current
        try? FileManager.default.createDirectory(at: presetsDirectoryURL, withIntermediateDirectories: true)
        let text = target.merged(into: Configuration.template)
        guard (try? text.write(to: presetURL(named: name), atomically: true, encoding: .utf8)) != nil else { return false }
        loadPresets()
        return true
    }

    /// Writes the preset's values into the live configuration and the config
    /// file. Later edits change the file, not the preset.
    @discardableResult
    func applyPreset(named name: String) -> Bool {
        guard let configuration = preset(named: name) else { return false }
        write(configuration)
        return true
    }

    func deletePreset(named name: String) {
        try? FileManager.default.removeItem(at: presetURL(named: name))
        loadPresets()
    }

    /// Replaces the live configuration directly. Used by tests and by the
    /// reload path; posts the change notification only when something differs.
    func apply(_ configuration: Configuration) {
        guard configuration != current else { return }
        current = configuration
        NotificationCenter.default.post(name: Configuration.didChangeNotification, object: self)
    }

    /// Applies a configuration and writes it into the file, preserving the
    /// file's comments and layout. The resulting watch event reloads an
    /// identical value and is a no-op.
    func write(_ configuration: Configuration) {
        apply(configuration)
        ensureFileExists()
        let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? Configuration.template
        try? configuration.merged(into: existing).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func reload() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        apply(Configuration.parse(text))
    }

    func ensureFileExists() {
        try? FileManager.default.createDirectory(at: presetsDirectoryURL, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? Configuration.template.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Watching

    /// Editors save either in place (a write event on the file) or by
    /// replacing it (a rename/delete on the file and a write on the
    /// directory). Both are watched, and the file watch is re-armed after a
    /// replacement so the new inode is followed.
    private func watch() {
        directorySource?.cancel()
        directorySource = makeSource(for: fileURL.deletingLastPathComponent(), events: .write) { [weak self] in
            self?.scheduleReload()
        }
        armFileSource()

        presetsSource?.cancel()
        presetsSource = makeSource(for: presetsDirectoryURL, events: .write) { [weak self] in
            self?.loadPresets()
        }
    }

    private func armFileSource() {
        fileSource?.cancel()
        fileSource = makeSource(for: fileURL, events: [.write, .extend, .delete, .rename, .attrib]) { [weak self] in
            self?.scheduleReload()
        }
    }

    private func makeSource(
        for url: URL,
        events: DispatchSource.FileSystemEvent,
        handler: @escaping @MainActor () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: events,
            queue: .main
        )
        source.setEventHandler {
            MainActor.assumeIsolated { handler() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    /// Coalesces bursts of events (an atomic save produces several) into one
    /// reload, then re-arms the file watch in case the inode changed.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let self else { return }
            self.reload()
            self.armFileSource()
        }
    }
}
