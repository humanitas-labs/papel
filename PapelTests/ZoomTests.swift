import AppKit
import Testing
@testable import Papel

/// The view scale is a lens over the page: every metric derived from the
/// body size and the measure follows it, chrome does not, and the config
/// never learns of it.
@MainActor
struct ZoomTests {
    private func withCleanZoom(_ body: () throws -> Void) rethrows {
        Zoom.reset()
        defer { Zoom.reset() }
        try body()
    }

    @Test
    func ladderClampsAtBothEndsAndResetLandsOnOne() {
        withCleanZoom {
            #expect(Zoom.scale == 1)
            for _ in 0..<20 { Zoom.zoomIn() }
            #expect(Zoom.scale == Zoom.range.upperBound)
            #expect(!Zoom.canZoomIn)
            #expect(Zoom.canZoomOut)
            for _ in 0..<40 { Zoom.zoomOut() }
            #expect(Zoom.scale == Zoom.range.lowerBound)
            #expect(!Zoom.canZoomOut)
            Zoom.reset()
            #expect(Zoom.scale == 1)
            #expect(UserDefaults.standard.object(forKey: Zoom.defaultsKey) == nil)
        }
    }

    @Test
    func stepsAreReproducibleFromEitherDirection() {
        withCleanZoom {
            Zoom.zoomIn(); Zoom.zoomIn()
            let up = Zoom.scale
            Zoom.zoomIn(); Zoom.zoomOut()
            #expect(Zoom.scale == up)
            Zoom.set(1.42)
            #expect(Zoom.scale == 1.42)
            #expect(Zoom.percent == 142)
            Zoom.zoomIn()
            #expect(Zoom.scale == 1.5)
            Zoom.set(percent: 83)
            Zoom.zoomOut()
            #expect(Zoom.scale == 0.8)
            Zoom.set(percent: 900)
            #expect(Zoom.scale == Zoom.range.upperBound)
            Zoom.set(0.001)
            #expect(Zoom.scale == Zoom.range.lowerBound)
            #expect(Zoom.observed.scale == Zoom.range.lowerBound)
        }
    }

    @Test
    func scalesTypeSystemAndMarginsButNotChrome() {
        withCleanZoom {
            let body = Appearance.bodySize
            let heading = Appearance.headingSize(level: 1)
            let indent = Appearance.listIndent
            let measure = Appearance.maximumMeasure
            let top = Appearance.topMargin
            let side = Appearance.minimumHorizontalMargin
            let radius = Appearance.codeBlockCornerRadius
            Zoom.set(1.5)
            #expect(Appearance.bodySize == body * 1.5)
            #expect(Appearance.headingSize(level: 1) == heading * 1.5)
            #expect(Appearance.listIndent == (body * 1.5 * CGFloat(Appearance.configuration.listIndent)).rounded())
            #expect(indent < Appearance.listIndent)
            #expect(Appearance.maximumMeasure == measure * 1.5)
            #expect(Appearance.topMargin == top * 1.5)
            #expect(Appearance.minimumHorizontalMargin == side * 1.5)
            #expect(Appearance.codeBlockCornerRadius == radius)
            #expect(Appearance.bodyFont().pointSize == body * 1.5)
        }
    }

    @Test
    func changePostsConfigurationNotificationAndLeavesConfigurationAlone() {
        withCleanZoom {
            let before = ConfigurationStore.shared.current
            var posts = 0
            let token = NotificationCenter.default.addObserver(
                forName: Configuration.didChangeNotification, object: nil, queue: nil
            ) { _ in posts += 1 }
            defer { NotificationCenter.default.removeObserver(token) }
            Zoom.zoomIn()
            Zoom.zoomIn()
            Zoom.set(Zoom.scale)
            #expect(posts == 2)
            #expect(ConfigurationStore.shared.current == before)
        }
    }
}
