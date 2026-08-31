import AppKit

/// Scroll view that animates discrete scrolling. A trackpad delivers
/// pixel-precise deltas with its own momentum and is left alone; a mouse
/// wheel notch or a keyboard page would jump the viewport, so those are
/// eased toward an accumulated target instead, the way browsers scroll.
final class PaperScrollView: NSScrollView {
    /// Points per wheel notch (a line-based delta of 1).
    static let notchDistance: CGFloat = 60
    /// The system accelerates line deltas — a spun wheel reports events of
    /// 10–20 lines. Multiplying those by the full notch distance launches
    /// the viewport, so acceleration is compressed and capped per event.
    static let accelerationExponent: CGFloat = 0.7
    static let maximumNotchesPerEvent: CGFloat = 4
    /// Duration of one easing run; further input extends the target, not
    /// the clock, so a spun wheel keeps moving without stalling.
    static let duration: TimeInterval = 0.18

    private var target: CGFloat?
    private var startOffset: CGFloat = 0
    private(set) var startTime: CFTimeInterval = 0
    private var displayLink: CADisplayLink?

    override func scrollWheel(with event: NSEvent) {
        guard !event.hasPreciseScrollingDeltas else {
            cancelAnimation()
            super.scrollWheel(with: event)
            return
        }
        guard event.scrollingDeltaY != 0 else {
            super.scrollWheel(with: event)
            return
        }
        // Sign already follows the user's natural-scrolling preference.
        scroll(by: -Self.distance(forLineDelta: event.scrollingDeltaY))
    }

    /// One slow notch keeps its full distance; larger, accelerated deltas
    /// grow sublinearly and never exceed a few notches per event.
    static func distance(forLineDelta lines: CGFloat) -> CGFloat {
        let notches = min(pow(abs(lines), accelerationExponent), maximumNotchesPerEvent)
        return copysign(notches * notchDistance, lines)
    }

    /// Animates the viewport by `distance` points, accumulating onto any
    /// animation in progress.
    func scroll(by distance: CGFloat) {
        let current = target ?? contentView.bounds.origin.y
        let clamped = min(max(current + distance, minimumOffset), maximumOffset)
        target = clamped
        startOffset = contentView.bounds.origin.y
        startTime = CACurrentMediaTime()
        if displayLink == nil {
            let link = displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    /// Stops the animation where it is; the next native event owns the
    /// viewport.
    func cancelAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        target = nil
    }

    private var minimumOffset: CGFloat { -contentInsets.top }

    private var maximumOffset: CGFloat {
        guard let document = documentView else { return 0 }
        return max(minimumOffset, document.frame.height + contentInsets.bottom - contentView.bounds.height)
    }

    @objc private func tick() {
        step(at: CACurrentMediaTime())
    }

    /// Advances the animation to `time`. The display link calls it with the
    /// current time; tests drive it directly.
    func step(at time: CFTimeInterval) {
        guard let target else { cancelAnimation(); return }
        let elapsed = time - startTime
        let progress = min(elapsed / Self.duration, 1)
        // Ease-out cubic: fast at first, settling into the target.
        let eased = 1 - pow(1 - progress, 3)
        let offset = startOffset + (target - startOffset) * eased
        var origin = contentView.bounds.origin
        origin.y = offset
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
        if progress >= 1 { cancelAnimation() }
    }
}
