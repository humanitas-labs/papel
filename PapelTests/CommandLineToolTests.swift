import Foundation
import Testing
@testable import Papel

/// The command-line installer against a fake bundle and PATH under a
/// temporary directory; the privileged path is never taken.
@MainActor
struct CommandLineToolTests {
    private struct Harness {
        let root: URL
        let launcher: URL
        let bin: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("cli-\(UUID().uuidString)")
            launcher = root.appendingPathComponent("Papel.app/Contents/Resources/papel")
            bin = root.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try "#!/bin/sh\n".write(to: launcher, atomically: true, encoding: .utf8)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }

        @MainActor func tool(path: [URL]? = nil) -> CommandLineTool {
            let tool = CommandLineTool(launcher: launcher)
            tool.useSearchPath(path ?? [bin])
            return tool
        }

        var link: URL { bin.appendingPathComponent("papel") }
    }

    private static func withoutOptOut<T>(_ body: () async throws -> T) async rethrows -> T {
        let key = "commandLineToolOptOut"
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        return try await body()
    }

    @Test
    func classifiesLinks() throws {
        let h = try Harness()
        defer { h.remove() }
        #expect(CommandLineTool.classify(link: nil, launcher: h.launcher) == .notInstalled)

        try FileManager.default.createSymbolicLink(at: h.link, withDestinationURL: h.launcher)
        #expect(CommandLineTool.classify(link: h.link, launcher: h.launcher) == .installed(h.link))

        let other = h.root.appendingPathComponent("Elsewhere/Papel.app/Contents/Resources/papel")
        try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: other, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: h.link)
        try FileManager.default.createSymbolicLink(at: h.link, withDestinationURL: other)
        #expect(CommandLineTool.classify(link: h.link, launcher: h.launcher) == .stale(h.link, target: other))

        try FileManager.default.removeItem(at: other)
        #expect(CommandLineTool.classify(link: h.link, launcher: h.launcher) == .broken(h.link))

        try FileManager.default.removeItem(at: h.link)
        try "#!/bin/sh\n".write(to: h.link, atomically: true, encoding: .utf8)
        #expect(CommandLineTool.classify(link: h.link, launcher: h.launcher) == .foreign(h.link))
    }

    @Test
    func candidatesKeepKnownExistingDirectoriesInPathOrder() throws {
        let h = try Harness()
        defer { h.remove() }
        let home = h.root.appendingPathComponent("home")
        let local = home.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        let path = [
            URL(fileURLWithPath: "/usr/bin"),
            local,
            home.appendingPathComponent("bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
        ]
        let expected = [local] + [URL(fileURLWithPath: "/opt/homebrew/bin"), URL(fileURLWithPath: "/usr/local/bin")]
            .filter(CommandLineTool.isDirectory)
        #expect(CommandLineTool.candidates(on: path, home: home).map(\.path) == expected.map(\.path))
    }

    @Test
    func installWritesRepairsAndUninstallRemoves() async throws {
        let h = try Harness()
        defer { h.remove() }
        try await Self.withoutOptOut {
            let tool = h.tool()
            await tool.refresh()
            #expect(tool.status == .notInstalled)

            // The Settings install in a non-candidate but writable PATH
            // directory falls through to a candidate; make bin a candidate
            // by writing the link directly first, as a stale one.
            try FileManager.default.createSymbolicLink(at: h.link, withDestinationURL: h.root.appendingPathComponent("Old.app/Contents/Resources/papel"))
            await tool.refresh()
            #expect(tool.status == .broken(h.link))

            await tool.install()
            #expect(tool.status == .installed(h.link))
            #expect(tool.lastError == nil)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: h.link.path) == h.launcher.path)

            await tool.uninstall()
            #expect(tool.status == .notInstalled)
            #expect(!CommandLineTool.isSymbolicLink(h.link))
            #expect(UserDefaults.standard.bool(forKey: "commandLineToolOptOut"))

            // Opted out: the quiet install stays away; the explicit one clears it.
            #expect(await tool.installQuietly() == .optedOut)
            #expect(tool.status == .notInstalled)
        }
    }

    @Test
    func quietInstallRepairsWritableLinksAndDeclinesUnwritableOnes() async throws {
        let h = try Harness()
        defer { h.remove() }
        try await Self.withoutOptOut {
            try FileManager.default.createSymbolicLink(at: h.link, withDestinationURL: h.root.appendingPathComponent("Old.app/Contents/Resources/papel"))
            let tool = h.tool()
            #expect(await tool.installQuietly() == .installed(h.link))
            #expect(tool.status == .installed(h.link))
            #expect(await tool.installQuietly() == .alreadyInstalled)

            // Another working copy keeps its link.
            let other = h.root.appendingPathComponent("Other.app/Contents/Resources/papel")
            try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\n".write(to: other, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: h.link)
            try FileManager.default.createSymbolicLink(at: h.link, withDestinationURL: other)
            #expect(await tool.installQuietly() == .alreadyInstalled)
            #expect(tool.status == .stale(h.link, target: other))

            try FileManager.default.removeItem(at: h.link)
            try FileManager.default.createSymbolicLink(at: h.link, withDestinationURL: h.root.appendingPathComponent("Old.app/Contents/Resources/papel"))
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: h.bin.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.bin.path) }
            let readOnly = h.tool()
            #expect(await readOnly.installQuietly() == .needsPrivileges)
            #expect(readOnly.status == .broken(h.link))
        }
    }

    @Test
    func quietInstallNeedsPrivilegesWhenNoKnownDirectoryIsWritable() async throws {
        let h = try Harness()
        defer { h.remove() }
        await Self.withoutOptOut {
            // bin is writable but not a known directory, so nothing is written.
            let tool = h.tool(path: [h.bin, URL(fileURLWithPath: "/usr/bin")])
            #expect(await tool.installQuietly() == .needsPrivileges)
            #expect(!CommandLineTool.isSymbolicLink(h.link))
        }
    }

    @Test
    func quotesShellArguments() {
        #expect(CommandLineTool.quoted("/Applications/Papel.app") == "'/Applications/Papel.app'")
        #expect(CommandLineTool.quoted("/it's/here") == "'/it'\\''s/here'")
    }
}
