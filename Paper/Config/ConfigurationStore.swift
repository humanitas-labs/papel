import Foundation

/// Owns the live configuration: loads the file, writes the template when it
/// is missing, and reloads whenever the file changes on disk. Every window
/// reads `current` and listens for `Configuration.didChangeNotification`.
@MainActor
final class ConfigurationStore: ObservableObject {
    static let shared = ConfigurationStore(fileURL: defaultFileURL)

    /// `$XDG_CONFIG_HOME/paper/config`, or `~/.config/paper/config`.
    static var defaultFileURL: URL {
        configurationBase.appendingPathComponent("paper", isDirectory: true).appendingPathComponent("config")
    }

    private static var configurationBase: URL {
        let environment = ProcessInfo.processInfo.environment
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
    }

    /// The app was first released as Serein; its `serein/` directory (config
    /// and presets) is moved to `paper/` once, when `paper/` does not exist.
    static func migrateLegacyConfiguration(in base: URL = configurationBase) {
        let legacy = base.appendingPathComponent("serein", isDirectory: true)
        let current = base.appendingPathComponent("paper", isDirectory: true)
        let manager = FileManager.default
        guard manager.fileExists(atPath: legacy.path), !manager.fileExists(atPath: current.path) else { return }
        try? manager.createDirectory(at: base, withIntermediateDirectories: true)
        try? manager.moveItem(at: legacy, to: current)
    }

    @Published private(set) var current = Configuration()
    /// Names of the saved presets, sorted, refreshed whenever the presets
    /// directory changes.
    @Published private(set) var presets: [String] = []
    /// The preset last applied or saved. Edits made while it is active are
    /// written into it, so the preset and the live settings never drift;
    /// cleared when the preset is deleted. Persisted per config file across
    /// launches.
    @Published private(set) var activePreset: String?
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
        activePreset = UserDefaults.standard.string(forKey: activePresetKey)
    }

    private var activePresetKey: String { "paper.activePreset:\(fileURL.path)" }

    private func setActivePreset(_ name: String?) {
        activePreset = name
        UserDefaults.standard.set(name, forKey: activePresetKey)
    }

    /// Creates the config file from the template if absent, loads it, and
    /// starts watching. Safe to call more than once.
    func start() {
        if fileURL == Self.defaultFileURL { Self.migrateLegacyConfiguration() }
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
        if let activePreset, !presets.contains(activePreset) {
            setActivePreset(nil)
        }
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
        if configuration == nil { setActivePreset(name.trimmingCharacters(in: .whitespaces)) }
        return true
    }

    /// Writes the preset's values into the live configuration and the config
    /// file. Later edits are written into the preset as well.
    @discardableResult
    func applyPreset(named name: String) -> Bool {
        guard let configuration = preset(named: name) else { return false }
        // Activate first so the write does not land in the previous preset.
        setActivePreset(name)
        write(configuration)
        return true
    }

    func deletePreset(named name: String) {
        try? FileManager.default.removeItem(at: presetURL(named: name))
        if activePreset == name { setActivePreset(nil) }
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
    /// file's comments and layout, and into the active preset when its values
    /// differ. The resulting watch events reload identical values and are
    /// no-ops.
    func write(_ configuration: Configuration) {
        apply(configuration)
        ensureFileExists()
        let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? Configuration.template
        try? configuration.merged(into: existing).write(to: fileURL, atomically: true, encoding: .utf8)
        if let activePreset, preset(named: activePreset) != configuration {
            savePreset(named: activePreset, configuration)
        }
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
