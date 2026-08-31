import Foundation
import Testing
@testable import Serein

struct ConfigurationTests {
    @Test
    func templateParsesToDefaults() {
        #expect(Configuration.parse(Configuration.template) == Configuration())
    }

    @Test
    func emptyAndCommentOnlyTextYieldDefaults() {
        #expect(Configuration.parse("") == Configuration())
        #expect(Configuration.parse("# nothing\n\n   \n# = still a comment\n") == Configuration())
    }

    @Test
    func parsesKeysWithWhitespaceQuotesAndCase() {
        let text = """
          Font.Family =  "New York"
        font.size=15.4
        line.height = '1.6'
        paragraph.spacing = 8
        measure = 720
        heading.weight = SemiBold
        """
        let config = Configuration.parse(text)
        #expect(config.fontFamily == "New York")
        #expect(config.fontSize == 15.4)
        #expect(config.lineHeight == 1.6)
        #expect(config.paragraphSpacing == 8)
        #expect(config.measure == 720)
        #expect(config.headingWeight == .semibold)
    }

    @Test
    func invalidValuesFallBackAndOutOfRangeValuesClamp() {
        let config = Configuration.parse("""
        font.size = large
        line.height = nan
        heading.weight = heavy
        measure = 10
        font.family =
        unknown.key = 1
        no equals sign here
        """)
        #expect(config.fontSize == Configuration().fontSize)
        #expect(config.lineHeight == Configuration().lineHeight)
        #expect(config.headingWeight == Configuration().headingWeight)
        #expect(config.measure == Configuration.measureRange.lowerBound)
        #expect(config.fontFamily == Configuration().fontFamily)
    }

    @Test
    func mergingUpdatesValuesInPlaceAndAppendsMissingKeys() {
        var config = Configuration()
        config.fontSize = 15.4
        config.headingWeight = .bold
        let text = "# keep me\nfont.size = 14   \nmystery = 1\n\nheading.weight = medium\n"
        let merged = config.merged(into: text)
        #expect(merged.hasPrefix("# keep me\nfont.size = 15.4\nmystery = 1\n\nheading.weight = bold\n"))
        #expect(merged.contains("\nfont.family = Test Family\n"))
        #expect(Configuration.parse(merged) == config)

        // Merging into the template only touches value lines.
        var defaults = Configuration()
        defaults.measure = 700
        let templated = defaults.merged(into: Configuration.template)
        #expect(templated == Configuration.template.replacingOccurrences(of: "measure = 640", with: "measure = 700"))
    }

    @Test
    func laterKeysOverrideEarlierOnes() {
        #expect(Configuration.parse("font.size = 12\nfont.size = 18").fontSize == 18)
    }
}

struct ThemeTests {
    @Test
    func hexParsesNormalizesAndRejects() {
        #expect(HexColor.normalized("#f6f3ec") == "#F6F3EC")
        #expect(HexColor.normalized(" 1B1916 ") == "#1B1916")
        #expect(HexColor.normalized("#FFF") == nil)
        #expect(HexColor.normalized("#GGGGGG") == nil)
        #expect(HexColor.normalized("") == nil)
        let c = HexColor.components("#FF8000")!
        #expect(c.red == 1 && c.green == 128.0 / 255 && c.blue == 0)
        #expect(HexColor.string(red: 1, green: 128.0 / 255, blue: 0) == "#FF8000")
    }

    @Test
    func themeKeysParseAndOverridesApply() {
        let config = Configuration.parse("""
        theme = Sepia
        color.ink = #102030
        color.canvas =
        color.ink.dark = nonsense
        """)
        #expect(config.theme == .sepia)
        #expect(config.ink == "#102030")
        #expect(config.canvas == nil)
        #expect(config.inkDark == nil, "invalid hex inherits the theme")
        #expect(config.palette.ink == "#102030")
        #expect(Configuration.parse("letter.spacing = -0.4").letterSpacing == -0.4)
        #expect(Configuration.parse("window.width = 1200\nwindow.height = 100").windowWidth == 1200)
        #expect(Configuration.parse("window.width = 1200\nwindow.height = 100").windowHeight == 520, "clamped")
        #expect(Configuration.parse("letter.spacing = 9").letterSpacing == 3, "clamped")
        #expect(config.palette.canvas == Theme.sepia.palette.canvas)
        #expect(config.palette.inkDark == Theme.sepia.palette.inkDark)
        #expect(Configuration.parse("theme = nope").theme == .paper)
        #expect(Configuration.parse("theme = Spatial-Dark").theme == .spatialDark)
        #expect(Theme.spatialDark.palette.canvas == Theme.spatialDark.palette.canvasDark)
        #expect(Configuration().palette == Theme.paper.palette)
    }

    @Test
    func mergedWritesEmptyOverridesAsBareKeys() {
        var config = Configuration()
        config.theme = .slate
        config.ink = "#123456"
        let text = config.merged(into: Configuration.template)
        #expect(text.contains("\ntheme = slate\n"))
        #expect(text.contains("\ncolor.ink = #123456\n"))
        #expect(text.contains("\ncolor.canvas =\n"))
        #expect(Configuration.parse(text) == config)
    }
}

@MainActor
struct ConfigurationStoreTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("serein-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config")
    }

    @Test
    func startWritesTemplateWhenMissingAndLoadsIt() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigurationStore(fileURL: url)
        store.start()
        #expect(try String(contentsOf: url, encoding: .utf8) == Configuration.template)
        #expect(store.current == Configuration())
    }

    @Test
    func startKeepsAnExistingFile() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "font.size = 21".write(to: url, atomically: true, encoding: .utf8)
        let store = ConfigurationStore(fileURL: url)
        store.start()
        #expect(store.current.fontSize == 21)
        #expect(try String(contentsOf: url, encoding: .utf8) == "font.size = 21")
    }

    @Test(arguments: [true, false])
    func reloadsWhenTheFileChanges(atomically: Bool) async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigurationStore(fileURL: url)
        store.start()
        #expect(store.current.fontSize == 14)

        try "font.size = 19\nmeasure = 700".write(to: url, atomically: atomically, encoding: .utf8)
        let deadline = ContinuousClock.now + .seconds(3)
        while store.current.fontSize != 19, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.current.fontSize == 19)
        #expect(store.current.measure == 700)

        // A second change after a replacement proves the watch re-armed.
        try "font.size = 23".write(to: url, atomically: atomically, encoding: .utf8)
        let secondDeadline = ContinuousClock.now + .seconds(3)
        while store.current.fontSize != 23, ContinuousClock.now < secondDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.current.fontSize == 23)
    }

    @Test
    func writePersistsIntoTheFilePreservingComments() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigurationStore(fileURL: url)
        store.start()
        var config = Configuration()
        config.lineHeight = 1.6
        store.write(config)
        #expect(store.current == config)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("line.height = 1.6"))
        #expect(text.hasPrefix("# Serein configuration."))
        #expect(Configuration.parse(text) == config)
    }

    @Test
    func presetsSaveApplyAndDelete() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigurationStore(fileURL: url)
        store.start()
        #expect(store.presets.isEmpty)
        #expect(store.matchingPreset == nil)

        var large = Configuration()
        large.fontSize = 18
        large.fontFamily = "Georgia"
        store.write(large)
        #expect(store.savePreset(named: "Reading"))
        #expect(store.savePreset(named: "Defaults", Configuration()))
        #expect(!store.savePreset(named: " "))
        #expect(!store.savePreset(named: "a/b"))
        #expect(store.presets == ["Defaults", "Reading"])
        #expect(store.matchingPreset == "Reading")
        #expect(FileManager.default.fileExists(atPath: store.presetURL(named: "Reading").path))

        #expect(store.applyPreset(named: "Defaults"))
        #expect(store.current == Configuration())
        #expect(store.matchingPreset == "Defaults")
        #expect(Configuration.parse(try String(contentsOf: url, encoding: .utf8)) == Configuration())

        var tweaked = store.current
        tweaked.lineHeight = 1.6
        store.write(tweaked)
        #expect(store.matchingPreset == nil, "editing after applying does not touch the preset")
        #expect(store.preset(named: "Defaults") == Configuration())

        #expect(!store.applyPreset(named: "Missing"))
        store.deletePreset(named: "Reading")
        #expect(store.presets == ["Defaults"])
    }

    @Test
    func activePresetSurvivesEditsAndUpdatesInPlace() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigurationStore(fileURL: url)
        store.start()
        defer { store.deletePreset(named: "Work") }

        store.savePreset(named: "Work")
        #expect(store.activePreset == "Work")
        #expect(!store.activePresetIsEdited)

        var edited = store.current
        edited.fontSize = 17
        store.write(edited)
        #expect(store.activePreset == "Work", "editing keeps the preset active")
        #expect(store.activePresetIsEdited)
        #expect(store.matchingPreset == nil)

        store.savePreset(named: "Work")
        #expect(!store.activePresetIsEdited)
        #expect(store.preset(named: "Work")?.fontSize == 17)

        let reopened = ConfigurationStore(fileURL: url)
        reopened.start()
        #expect(reopened.activePreset == "Work", "persists across launches")

        store.deletePreset(named: "Work")
        #expect(store.activePreset == nil)
    }

    @Test
    func applyPostsOnlyOnChange() {
        let store = ConfigurationStore(fileURL: temporaryFile())
        nonisolated(unsafe) var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: Configuration.didChangeNotification, object: store, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        store.apply(Configuration())
        var changed = Configuration()
        changed.fontSize = 16
        store.apply(changed)
        store.apply(changed)
        #expect(posts == 1)
    }
}
