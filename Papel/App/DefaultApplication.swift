import AppKit
import UniformTypeIdentifiers

/// Papel as the app a double-click on a Markdown file opens: what Get
/// Info's Change All does, set from code instead. `papel --set-default`
/// runs the app's executable with the same flag; it sets the default and
/// exits before any window opens, so an agent can do it on the user's
/// word. Settings ▸ CLI has a button for the same thing.
enum DefaultApplication {
    static let flag = "--set-default"

    /// `net.daringfireball.markdown`, which `.md` and `.markdown` resolve
    /// to; the bundle imports it, so it is always known in-process.
    static var markdown: UTType? { UTType("net.daringfireball.markdown") }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Whether Papel is what opens Markdown files now. Launch Services keeps
    /// the default by bundle identifier and answers with whichever copy it
    /// prefers, so the identifier is compared, not the path.
    @MainActor
    static var isDefault: Bool {
        guard let markdown, let handler = NSWorkspace.shared.urlForApplication(toOpen: markdown) else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Makes this copy of Papel the default for Markdown files.
    @MainActor
    static func makeDefault() async throws {
        guard let markdown else {
            throw Failure(errorDescription: "the Markdown document type is not registered")
        }
        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: markdown)
    }

    /// Whether the process was started with the flag, from the launcher.
    static var requestedOnCommandLine: Bool {
        CommandLine.arguments.dropFirst().contains(flag)
    }

    /// Sets the default, reports on the standard streams, and exits. Called
    /// from the app's initialiser, before the application runs; the main
    /// run loop is spun by hand until Launch Services answers.
    @MainActor
    static func runFromCommandLine() -> Never {
        if isDefault {
            print("Papel already opens Markdown files.")
            exit(0)
        }
        var outcome: Result<Void, Error>?
        Task { @MainActor in
            do {
                try await makeDefault()
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
        }
        while outcome == nil {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        switch outcome {
        case .success, .none:
            print("Papel now opens Markdown files (.md, .markdown).")
            exit(0)
        case .failure(let error):
            FileHandle.standardError.write(Data("papel: could not make Papel the default app for Markdown: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
