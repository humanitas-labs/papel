import Foundation
import Testing
@testable import Papel

struct UpdateCheckTests {
    @Test
    func newerComparesDottedNumbers() {
        #expect(UpdateCheck.isNewer("0.6.1", than: "0.6.0"))
        #expect(!UpdateCheck.isNewer("0.6.0", than: "0.6.0"))
        #expect(!UpdateCheck.isNewer("0.5.9", than: "0.6.0"))
        #expect(UpdateCheck.isNewer("0.10.0", than: "0.9.0"), "numeric, not lexical")
        #expect(UpdateCheck.isNewer("v0.7", than: "0.6.1"), "a tag's v is dropped; a missing component is 0")
        #expect(!UpdateCheck.isNewer("0.6", than: "0.6.0"))
        #expect(UpdateCheck.isNewer("1.0.0", than: "0.99.99"))
        #expect(!UpdateCheck.isNewer("garbage", than: "0.6.0"), "never nag on a bad tag")
        #expect(!UpdateCheck.isNewer("0.7.0", than: "garbage"))
        #expect(!UpdateCheck.isNewer("0.7.0", than: ""))
    }

    @Test
    func releaseParsesTheTagAndPointsAtTheStableDownload() {
        let body = Data(#"{"tag_name":"v0.7.0","name":"Papel 0.7.0","assets":[{"name":"Papel.dmg"}]}"#.utf8)
        let release = UpdateCheck.release(from: body)
        #expect(release?.version == "0.7.0")
        #expect(release?.url.absoluteString == "https://github.com/humanitas-labs/papel/releases/latest/download/Papel.dmg")
        #expect(UpdateCheck.release(from: Data(#"{"tag_name":"0.8"}"#.utf8))?.version == "0.8", "no v is fine")
        #expect(UpdateCheck.release(from: Data(#"{"message":"Not Found"}"#.utf8)) == nil, "no tag is no release")
        #expect(UpdateCheck.release(from: Data(#"{"tag_name":"nightly"}"#.utf8)) == nil, "a non-numeric tag is ignored")
        #expect(UpdateCheck.release(from: Data("<html>".utf8)) == nil)
    }

    @Test
    func dueOnceADay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UpdateCheck.isDue(lastCheck: nil, now: now))
        #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
    }

    @Test
    func configurationKey() {
        #expect(Configuration().updateCheck, "on by default")
        #expect(!Configuration.parse("update.check = off").updateCheck)
        #expect(Configuration.parse("update.check = sometimes").updateCheck, "an unknown value keeps the default")
        #expect(Configuration.parse("update.check = off").entries.contains { $0.key == "update.check" && $0.value == "off" })
        #expect(Configuration.parse(Configuration.template) == Configuration(), "the template still parses to the defaults")
    }

    @MainActor
    @Test
    func offNeverTouchesDefaultsAndAKnownReleaseShowsWithoutANetwork() {
        let defaults = UserDefaults(suiteName: "papel.tests.update.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        var off = Configuration()
        off.updateCheck = false
        UpdateCheck.runIfDue(configuration: off, defaults: defaults, current: "0.6.0")
        #expect(defaults.object(forKey: UpdateCheck.lastCheckKey) == nil, "off makes no check and records nothing")

        // A release found earlier today shows at once; the check is not
        // due, so no request goes out and lastCheck stays put.
        let now = Date()
        defaults.set(now.addingTimeInterval(-3600), forKey: UpdateCheck.lastCheckKey)
        defaults.set("0.7.0", forKey: UpdateCheck.availableKey)
        UpdateCheck.observed.available = nil
        UpdateCheck.runIfDue(configuration: Configuration(), defaults: defaults, current: "0.6.0", now: now)
        #expect(UpdateCheck.observed.available?.version == "0.7.0")
        #expect((defaults.object(forKey: UpdateCheck.lastCheckKey) as? Date) == now.addingTimeInterval(-3600))

        // Once the app catches up the remembered release is dropped.
        UpdateCheck.observed.available = nil
        UpdateCheck.runIfDue(configuration: Configuration(), defaults: defaults, current: "0.7.0", now: now)
        #expect(UpdateCheck.observed.available == nil)
        #expect(defaults.string(forKey: UpdateCheck.availableKey) == nil)
    }
}
