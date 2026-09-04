import SwiftUI

/// The note after an update: a checkmark and "Updated to version 0.7.0"
/// in a capsule dropped from the top centre of the first window after the
/// relaunch. It fades in, stays a few seconds, and fades out; a click
/// dismisses it early.
struct UpdateToast: View {
    @ObservedObject private var updates = UpdateCheck.observed
    @ObservedObject private var store = ConfigurationStore.shared
    @State private var visible = false
    @State private var hide: Task<Void, Never>?
    /// The traffic lights' centre line, from the window's top edge, so the
    /// capsule sits level with them; read from the window the toast is in,
    /// as the title band settles. Half the unified toolbar's height until
    /// the window reports.
    @State private var centreLine: CGFloat = 26

    var body: some View {
        Group {
            if let version = updates.justUpdatedTo {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(nsColor: Appearance.accent))
                    Text("Updated to version \(version)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: Appearance.ink))
                }
                .padding(.leading, 12)
                .padding(.trailing, 15)
                .padding(.vertical, 7)
                .background(Color(nsColor: Appearance.canvas), in: Capsule())
                .overlay(Capsule().stroke(Color(nsColor: Appearance.thematicBreakInk), lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
                .padding(.top, max(0, centreLine - 14))
                .background(TitleBandReader(centreLine: $centreLine))
                .ignoresSafeArea(.container, edges: .top)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : -(centreLine + 40))
                .contentShape(Capsule())
                .onTapGesture { dismiss() }
                .onAppear {
                    // A beat after the window lands, then it drops in and
                    // settles with a little spring.
                    hide = Task {
                        try? await Task.sleep(for: .seconds(0.4))
                        guard !Task.isCancelled else { return }
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) { visible = true }
                        try? await Task.sleep(for: .seconds(5.5))
                        guard !Task.isCancelled else { return }
                        dismiss()
                    }
                }
            }
        }
    }

    /// Where the close button's centre sits below the top edge of
    /// `window`, in points; the middle of the title band when the button
    /// has no frame yet.
    @MainActor
    static func trafficLightCentreLine(in window: NSWindow) -> CGFloat {
        if let close = window.standardWindowButton(.closeButton),
           let frame = close.superview?.convert(close.frame, to: nil), frame.height > 0 {
            return window.frame.height - frame.midY
        }
        return max(window.frame.height - window.contentLayoutRect.height, 0) / 2
    }

    private func dismiss() {
        hide?.cancel()
        withAnimation(.easeIn(duration: 0.35)) { visible = false }
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            updates.justUpdatedTo = nil
        }
    }
}

/// A zero-size view under the toast that reads the traffic lights' centre
/// line from the window it lands in, and again whenever the title band
/// changes (the chrome adds its toolbar after the window shows). The toast
/// can appear before any window is key, so it cannot ask the app.
private struct TitleBandReader: NSViewRepresentable {
    @Binding var centreLine: CGFloat

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.report = { centreLine = $0 }
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.report = { centreLine = $0 }
    }

    final class ReaderView: NSView {
        var report: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.contentLayoutRect, options: [.initial]) { [weak self] window, _ in
                MainActor.assumeIsolated {
                    guard let self, self.window === window else { return }
                    let line = UpdateToast.trafficLightCentreLine(in: window)
                    Task { @MainActor in self.report?(line) }
                }
            }
        }
    }
}
