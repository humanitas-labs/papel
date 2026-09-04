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
    /// capsule sits level with them. The unified toolbar's height when no
    /// window is up yet.
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
                .ignoresSafeArea(.container, edges: .top)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : -(centreLine + 40))
                .contentShape(Capsule())
                .onTapGesture { dismiss() }
                .onAppear {
                    if let line = Self.trafficLightCentreLine() { centreLine = line }
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

    /// Where the close button's centre sits below the top edge of the
    /// front window, in points.
    @MainActor
    static func trafficLightCentreLine() -> CGFloat? {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible),
              let close = window.standardWindowButton(.closeButton),
              let frame = close.superview?.convert(close.frame, to: nil) else { return nil }
        return window.frame.height - frame.midY
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
