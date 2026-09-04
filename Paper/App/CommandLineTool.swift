import AppKit
import Foundation

/// The `paper` command: a symlink on the PATH to the launcher script in
/// the bundle. The link is what is installed, so the command follows the
/// app through updates; it breaks only when the app moves, and the same
/// install rewrites it.
///
/// Installation is quiet when it costs nothing: at launch, a link goes into
/// the first user-writable directory on the login shell's PATH. When only
/// a root-owned directory such as /usr/local/bin is available, nothing
/// happens until the user asks in Settings, where the install runs with
/// administrator privileges.
@MainActor
final class CommandLineTool: ObservableObject {
    static let shared = CommandLineTool(
        launcher: Bundle.main.resourceURL!.appendingPathComponent("paper"))

    enum Status: Equatable {
        /// No `paper` on the PATH.
        case notInstalled
        /// A link to this app's launcher.
        case installed(URL)
        /// A link to a launcher that no longer exists: the app moved.
        case broken(URL)
        /// A link to a launcher inside a different copy of the app.
        case stale(URL, target: URL)
        /// A `paper` on the PATH that is not a link to a Paper bundle; left alone.
        case foreign(URL)

        var link: URL? {
            switch self {
            case .notInstalled: nil
            case .installed(let url), .broken(let url), .stale(let url, _), .foreign(let url): url
            }
        }

        var needsInstall: Bool {
            switch self {
            case .notInstalled, .broken, .stale: true
            case .installed, .foreign: false
            }
        }
    }

    /// What the launch-time install did; the source for any later hint.
    enum QuietOutcome: Equatable {
        /// Ours, another working copy's, or someone else's: left as it is.
        case alreadyInstalled
        case installed(URL)
        /// Every PATH directory needs privileges; Settings can finish it.
        case needsPrivileges
        /// The user removed the command in Settings; it stays removed.
        case optedOut
        case failed(String)
    }

    /// Directories the quiet install considers, in PATH order. Others on
    /// the PATH are read for an existing link but never written to.
    static let knownDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin", "~/bin"]
    static let privilegedDirectory = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
    static let name = "paper"
    private static let optOutKey = "commandLineToolOptOut"

    @Published private(set) var status: Status = .notInstalled
    @Published private(set) var lastError: String?
    private(set) var quietOutcome: QuietOutcome?

    let launcher: URL
    private let fileManager = FileManager.default
    private var searchPath: [URL]?

    init(launcher: URL) {
        self.launcher = launcher
    }

    // MARK: Reading

    /// Re-reads the PATH and the link, if any, and publishes the status.
    func refresh() async {
        let path = await loginShellPath()
        status = Self.classify(link: Self.existingLink(on: path), launcher: launcher)
    }

    /// The first `paper` on the PATH, following `which`.
    static func existingLink(on path: [URL]) -> URL? {
        path.map { $0.appendingPathComponent(name) }
            .first { (try? $0.checkResourceIsReachable()) == true || isSymbolicLink($0) }
    }

    static func classify(link: URL?, launcher: URL) -> Status {
        guard let link else { return .notInstalled }
        guard isSymbolicLink(link),
              let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        else { return .foreign(link) }
        let target = URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent()).standardizedFileURL
        guard target.path.hasSuffix("/Contents/Resources/\(name)") else { return .foreign(link) }
        if target.path == launcher.standardizedFileURL.path { return .installed(link) }
        if FileManager.default.fileExists(atPath: target.path) { return .stale(link, target: target) }
        return .broken(link)
    }

    /// Directories from `path` the quiet install may write to, in PATH
    /// order, existing only, and only those in `knownDirectories`.
    static func candidates(on path: [URL], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let known = Set(knownDirectories.map { entry -> String in
            entry.hasPrefix("~/") ? home.appendingPathComponent(String(entry.dropFirst(2))).path : entry
        })
        return path.filter { known.contains($0.path) && isDirectory($0) }
    }

    static func isWritable(_ directory: URL) -> Bool {
        access(directory.path, W_OK) == 0
    }

    // MARK: Writing

    /// The launch-time install: writes a missing link or repairs a broken
    /// one, only where no password is needed, and never after the user
    /// removed it. A link to another working copy of the app is left alone;
    /// Settings offers the repair.
    @discardableResult
    func installQuietly() async -> QuietOutcome {
        let outcome = await quietInstall()
        if case .installed = outcome { await refresh() }
        quietOutcome = outcome
        return outcome
    }

    private func quietInstall() async -> QuietOutcome {
        if UserDefaults.standard.bool(forKey: Self.optOutKey) { return .optedOut }
        await refresh()
        switch status {
        case .installed, .foreign, .stale:
            return .alreadyInstalled
        case .broken(let link):
            guard Self.isWritable(link.deletingLastPathComponent()) else { return .needsPrivileges }
            do {
                try writeLink(at: link)
                return .installed(link)
            } catch {
                return .failed(error.localizedDescription)
            }
        case .notInstalled:
            let path = await loginShellPath()
            guard let directory = Self.candidates(on: path).first(where: Self.isWritable) else {
                return .needsPrivileges
            }
            let link = directory.appendingPathComponent(Self.name)
            do {
                try writeLink(at: link)
                return .installed(link)
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    /// The Settings action: repairs an existing link in place, otherwise
    /// writes one into the first writable known directory, otherwise into
    /// /usr/local/bin with administrator privileges.
    func install() async {
        UserDefaults.standard.removeObject(forKey: Self.optOutKey)
        lastError = nil
        await refresh()
        let link: URL
        switch status {
        case .installed, .foreign:
            return
        case .broken(let existing), .stale(let existing, _):
            link = existing
        case .notInstalled:
            let path = await loginShellPath()
            let directory = Self.candidates(on: path).first(where: Self.isWritable) ?? Self.privilegedDirectory
            link = directory.appendingPathComponent(Self.name)
        }
        do {
            if Self.isWritable(link.deletingLastPathComponent()) {
                try writeLink(at: link)
            } else {
                try Self.runPrivileged(
                    "mkdir -p \(Self.quoted(link.deletingLastPathComponent().path)) && ln -sfn \(Self.quoted(launcher.path)) \(Self.quoted(link.path))")
            }
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    /// Removes the link and remembers the choice, so a later launch does
    /// not put it back.
    func uninstall() async {
        lastError = nil
        await refresh()
        guard let link = status.link, status != .foreign(link) else { return }
        do {
            if Self.isWritable(link.deletingLastPathComponent()) {
                try fileManager.removeItem(at: link)
            } else {
                try Self.runPrivileged("rm -f \(Self.quoted(link.path))")
            }
            UserDefaults.standard.set(true, forKey: Self.optOutKey)
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    /// Replaces whatever is at `link` with a symlink to the launcher.
    func writeLink(at link: URL) throws {
        if Self.isSymbolicLink(link) || fileManager.fileExists(atPath: link.path) {
            try fileManager.removeItem(at: link)
        }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: launcher)
    }

    struct PrivilegedError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Runs a shell command with administrator privileges through the
    /// system's password prompt, the way the `code` and `zed` commands
    /// install theirs. A cancelled prompt throws.
    static func runPrivileged(_ command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "The command could not be run."
            throw PrivilegedError(message: message)
        }
    }

    static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: PATH

    /// The PATH of the user's login shell, which is where `paper` has to be
    /// found; the app's own environment is the launchd one. Read once.
    func loginShellPath() async -> [URL] {
        if let searchPath { return searchPath }
        let path = await Task.detached(priority: .userInitiated) { Self.readLoginShellPath() }.value
        searchPath = path
        return path
    }

    /// Lets a test supply the PATH instead of asking the shell.
    func useSearchPath(_ path: [URL]) {
        searchPath = path
    }

    private nonisolated static func readLoginShellPath() -> [URL] {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "printf '%s' \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var output = ""
        if (try? process.run()) != nil {
            output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
        }
        if output.isEmpty {
            output = ProcessInfo.processInfo.environment["PATH"] ?? ""
        }
        return output.split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) }
    }

    // MARK: File helpers

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
