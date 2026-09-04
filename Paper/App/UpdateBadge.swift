import SwiftUI

/// The badge in a window's bottom-left corner, the welcome window's and
/// every document's, out of the way of the text, shown only while a
/// newer release is about. It is the one coloured thing on the page, in
/// the theme's accent. A down arrow says a release is out and a click
/// installs it; a ring fills as it downloads and installs; then a restart
/// loop takes its place, bobbing while the pointer rests on it, and a
/// click relaunches. Nothing is downloaded until asked. After a failure a
/// dotted arrow opens the browser download instead.
struct UpdateBadge: View {
    let release: UpdateCheck.Release
    @ObservedObject private var updates = UpdateCheck.observed
    @State private var hovering = false
    @State private var shown = false
    @State private var bobbing = false

    private var clickable: Bool {
        switch updates.phase {
        case .found, .ready, .failed: true
        case .installing: false
        }
    }

    private var help: String {
        switch updates.phase {
        case .found: "Paper \(release.version) is available. Click to install"
        case .installing: "Installing Paper \(release.version)…"
        case .ready: "Paper \(release.version) is ready. Click to restart"
        case .failed: "Couldn't install Paper \(release.version); click to download it"
        }
    }

    var body: some View {
        Button { UpdateCheck.activate(release) } label: {
            ZStack {
                switch updates.phase {
                case .found:
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 14, weight: .regular))
                case .installing(let fraction):
                    ProgressRing(fraction: fraction)
                case .ready:
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .regular))
                case .failed:
                    Image(systemName: "arrow.down.circle.dotted")
                        .font(.system(size: 14, weight: .regular))
                }
            }
            .foregroundStyle(Color(nsColor: Appearance.accent).opacity(hovering && clickable ? 1 : 0.78))
            .offset(y: bobbing ? -5 : 0)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!clickable)
        .help(help)
        .accessibilityLabel(help)
        .onHover { inside in
            hovering = inside
            if inside, clickable {
                withAnimation(.easeInOut(duration: 0.32).repeatForever(autoreverses: true)) { bobbing = true }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { bobbing = false }
            }
        }
        .pointerStyle(clickable ? .link : .default)
        .padding(.bottom, 12)
        .padding(.leading, 12)
        .opacity(shown ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: updates.phase)
        .onAppear { withAnimation(.easeOut(duration: 0.45)) { shown = true } }
    }
}

/// A 13-point ring: the download's fraction as an arc, or a slow spin
/// while the fraction is unknown.
struct ProgressRing: View {
    let fraction: Double?
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 1.2).opacity(0.25)
            Circle()
                .trim(from: 0, to: fraction ?? 0.3)
                .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 270 : -90))
                .animation(fraction == nil ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .easeOut(duration: 0.2), value: spinning)
                .animation(.easeOut(duration: 0.2), value: fraction)
        }
        .frame(width: 13, height: 13)
        .onAppear { spinning = fraction == nil }
        .onChange(of: fraction == nil) { _, unknown in spinning = unknown }
    }
}
