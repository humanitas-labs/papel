import AppKit
import Security

/// Installs a release in place, the way Zed does: download the DMG, mount
/// it, check that the app inside is signed by Apple's chain for this
/// bundle identifier (and this team, when the running copy names one),
/// swap it in over the running bundle, and relaunch. The old copy is
/// removed once the new one is in place; nothing is left in Downloads.
/// Any failure leaves the running app untouched and falls back to the
/// browser download.
enum UpdateInstaller {
    enum Failure: Error, Equatable {
        case download
        case mount
        case noApp
        case signature(String)
        case notWritable
        case swap(String)
    }

    /// The whole run. Progress is 0…1 for the download, then indeterminate.
    static func install(
        _ release: UpdateCheck.Release,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        let installed = Bundle.main.bundleURL
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("papel-update-\(release.version)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        guard FileManager.default.isWritableFile(atPath: installed.deletingLastPathComponent().path) else {
            throw Failure.notWritable
        }

        let dmg = scratch.appendingPathComponent("Papel.dmg")
        try await download(release.url, to: dmg, progress: progress)
        progress(nil)

        let mount = scratch.appendingPathComponent("mount", isDirectory: true)
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen",
                                        "-mountpoint", mount.path, dmg.path]).ok else {
            throw Failure.mount
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }

        let mounted = mount.appendingPathComponent(installed.lastPathComponent)
        guard FileManager.default.fileExists(atPath: mounted.path) else { throw Failure.noApp }
        try verify(mounted, against: installed)

        // Copied off the image before the swap so the mount can go and the
        // new bundle is a plain directory the swap can rename.
        let staged = scratch.appendingPathComponent(installed.lastPathComponent)
        guard run("/usr/bin/ditto", [mounted.path, staged.path]).ok else { throw Failure.swap("copy") }
        try replace(installed, with: staged)
    }

    // MARK: - Steps

    private static func download(
        _ url: URL, to destination: URL, progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("Papel/\(UpdateCheck.bundleVersion)", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        guard let (bytes, response) = try? await session.bytes(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        let expected = response.expectedContentLength
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: destination) else { throw Failure.download }
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var received: Int64 = 0
        var lastReported = -1.0
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1 << 16 {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if expected > 0 {
                        let fraction = Double(received) / Double(expected)
                        if fraction - lastReported >= 0.01 { lastReported = fraction; progress(fraction) }
                    }
                }
            }
            try handle.write(contentsOf: buffer)
        } catch {
            throw Failure.download
        }
    }

    /// Signed through Apple's chain, for this bundle identifier, and by the
    /// running copy's team when it has one. A development build with no
    /// team accepts any Apple-issued signature for the identifier.
    static func verify(_ candidate: URL, against installed: URL) throws {
        let requirement = try requirementString(for: installed)
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(candidate as CFURL, [], &code) == errSecSuccess, let code else {
            throw Failure.signature("unreadable")
        }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else {
            throw Failure.signature("requirement")
        }
        var error: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidityWithErrors(code, flags, req, &error) == errSecSuccess else {
            let message = (error?.takeRetainedValue()).map { String(describing: $0) } ?? "invalid"
            throw Failure.signature(message)
        }
    }

    /// The designated requirement a download must meet, from the running
    /// copy's own signature.
    static func requirementString(for installed: URL) throws -> String {
        let identifier = Bundle(url: installed)?.bundleIdentifier ?? "org.humanitas.papel"
        var requirement = "anchor apple generic and identifier \"\(identifier)\""
        if let team = teamIdentifier(of: installed) {
            requirement += " and certificate leaf[subject.OU] = \"\(team)\""
        }
        return requirement
    }

    static func teamIdentifier(of bundle: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Moves `installed` aside, puts `candidate` in its place, and removes
    /// the old copy. If the second move fails the old copy comes back.
    static func replace(_ installed: URL, with candidate: URL) throws {
        let fm = FileManager.default
        let aside = installed.deletingLastPathComponent()
            .appendingPathComponent(".\(installed.lastPathComponent).old-\(UUID().uuidString)")
        do {
            try fm.moveItem(at: installed, to: aside)
        } catch {
            throw Failure.swap("move aside: \(error.localizedDescription)")
        }
        do {
            try fm.moveItem(at: candidate, to: installed)
        } catch {
            try? fm.moveItem(at: aside, to: installed)
            throw Failure.swap("move in: \(error.localizedDescription)")
        }
        try? fm.removeItem(at: aside)
    }

    /// Quits and reopens the bundle at its path once this process is gone.
    /// A cancelled quit (an unsaved document kept open) leaves the new copy
    /// in place for the next launch.
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"\(path)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String]) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (false, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
    }
}
