import Foundation
import Testing
@testable import Papel

struct UpdateInstallerTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("papel-installer-tests-\(UUID().uuidString)", isDirectory: true)
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
        let installed = root.appendingPathComponent("Papel.app")
        let candidate = root.appendingPathComponent("stage/Papel.app")
        try bundle(at: installed, marker: "old")
        try bundle(at: candidate, marker: "new")
        try UpdateInstaller.replace(installed, with: candidate)
        #expect(try String(contentsOf: installed.appendingPathComponent("Contents/marker"), encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: candidate.path), "moved, not copied")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".Papel.app.old") }
        #expect(leftovers.isEmpty, "the old copy is gone")
    }

    @Test
    func replaceRestoresTheOldCopyWhenTheNewOneCannotMoveIn() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Papel.app")
        try bundle(at: installed, marker: "old")
        let missing = root.appendingPathComponent("nowhere/Papel.app")
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
        let fake = root.appendingPathComponent("Papel.app")
        try bundle(at: fake, marker: "fake")
        #expect(throws: UpdateInstaller.Failure.self) {
            try UpdateInstaller.verify(fake, against: Bundle.main.bundleURL)
        }
    }
}
