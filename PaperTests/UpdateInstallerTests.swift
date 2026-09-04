import Foundation
import Testing
@testable import Paper

struct UpdateInstallerTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paper-installer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func bundle(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try marker.write(to: url.appendingPathComponent("Contents/marker"), atomically: true, encoding: .utf8)
    }

    @Test
    func replaceSwapsTheBundleAndRemovesTheOldCopy() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Paper.app")
        let candidate = root.appendingPathComponent("stage/Paper.app")
        try bundle(at: installed, marker: "old")
        try bundle(at: candidate, marker: "new")
        try UpdateInstaller.replace(installed, with: candidate)
        #expect(try String(contentsOf: installed.appendingPathComponent("Contents/marker"), encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: candidate.path), "moved, not copied")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".Paper.app.old") }
        #expect(leftovers.isEmpty, "the old copy is gone")
    }

    @Test
    func replaceRestoresTheOldCopyWhenTheNewOneCannotMoveIn() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Paper.app")
        try bundle(at: installed, marker: "old")
        let missing = root.appendingPathComponent("nowhere/Paper.app")
        #expect(throws: UpdateInstaller.Failure.self) {
            try UpdateInstaller.replace(installed, with: missing)
        }
        #expect(try String(contentsOf: installed.appendingPathComponent("Contents/marker"), encoding: .utf8) == "old")
    }

    @Test
    func requirementNamesTheIdentifierAndTheTeamWhenThereIsOne() throws {
        // The test host is ad-hoc signed: no team, so any Apple-issued
        // signature for the identifier passes.
        let requirement = try UpdateInstaller.requirementString(for: Bundle.main.bundleURL)
        #expect(requirement.hasPrefix("anchor apple generic and identifier \""))
        if UpdateInstaller.teamIdentifier(of: Bundle.main.bundleURL) == nil {
            #expect(!requirement.contains("subject.OU"))
        } else {
            #expect(requirement.contains("certificate leaf[subject.OU] = \""))
        }
    }

    @Test
    func anUnsignedBundleFailsVerification() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = root.appendingPathComponent("Paper.app")
        try bundle(at: fake, marker: "fake")
        #expect(throws: UpdateInstaller.Failure.self) {
            try UpdateInstaller.verify(fake, against: Bundle.main.bundleURL)
        }
    }

    @Test
    func theAppOnTheImageIsFoundByExtensionNotByName() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try bundle(at: root.appendingPathComponent("Papel.app"), marker: "old-name")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Applications"), withDestinationURL: URL(fileURLWithPath: "/Applications"))
        #expect(UpdateInstaller.app(inside: root)?.lastPathComponent == "Papel.app")
        try bundle(at: root.appendingPathComponent("Other.app"), marker: "second")
        #expect(UpdateInstaller.app(inside: root) == nil, "two apps is not a release image")
        #expect(UpdateInstaller.app(inside: root.appendingPathComponent("nowhere")) == nil)
    }
}
