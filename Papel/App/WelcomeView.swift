import AppKit
import SwiftUI

/// The welcome window's content: the mark over a greeting, a Get Started
/// list, and the recent documents, set on the theme's canvas in its inks so
/// it reads as a Papel page rather than a system panel. Lists are in the
/// system sans at Zed's sizes; only the greeting is in the serif. Actions
/// leave the window up; it closes itself once a document window opens, so
/// a cancelled Open panel lands back here.
struct WelcomeView: View {
    let recents: [WelcomeModel.Recent]
    let greeting: String
    /// Observed so a theme or font change restyles the open window.
    @ObservedObject private var store = ConfigurationStore.shared
    /// Set once the launch check finds a newer release.
    @ObservedObject private var updates = UpdateCheck.observed

    static let columnWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)
            section("Get started") {
                row("New file", symbol: "plus", hint: "⌘N") {
                    NSDocumentController.shared.newDocument(nil)
                }
                row("Open…", symbol: "folder", hint: "⌘O") {
                    NSDocumentController.shared.openDocument(nil)
                }
                row("Settings", symbol: "slider.horizontal.3", hint: "⌘,") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                row("Guide", symbol: "book", hint: "") {
                    Task { await WelcomeDocument.open(replacing: false) }
                }
            }
            if !recents.isEmpty {
                section("Recent") {
                    ForEach(Array(recents.enumerated()), id: \.element.id) { index, recent in
                        row(recent.name, detail: recent.folder, symbol: "doc.text", hint: "⌘\(index + 1)") {
                            NSDocumentController.shared.openDocument(
                                withContentsOf: recent.url, display: true
                            ) { _, _, _ in }
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    }
                }
                .padding(.top, 20)
            }
        }
        .frame(width: Self.columnWidth)
        // Optically centred: a touch above the geometric middle.
        .padding(.bottom, 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Appearance.canvas))
        .overlay(alignment: .bottomLeading) {
            if let release = updates.available, updates.justUpdatedTo == nil {
                UpdateBadge(release: release)
            }
        }
        .overlay(alignment: .top) { UpdateToast().ignoresSafeArea(.container, edges: .top) }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image("Enso")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color(nsColor: Appearance.ink))
                .frame(width: 44, height: 44)
            Text(greeting)
                .font(Font(Appearance.font(size: 17, weight: 400, italic: false)))
                .foregroundStyle(Color(nsColor: Appearance.ink))
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(title.uppercased())
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(Color(nsColor: Appearance.labelInk))
                Rectangle()
                    .fill(Color(nsColor: Appearance.thematicBreakInk))
                    .frame(height: 1)
            }
            .padding(.bottom, 6)
            content()
        }
    }

    private func row(
        _ title: String, detail: String? = nil, symbol: String, hint: String, action: @escaping () -> Void
    ) -> some View {
        WelcomeRow(title: title, detail: detail, symbol: symbol, hint: hint, action: action)
    }
}

private struct WelcomeRow: View {
    let title: String
    let detail: String?
    let symbol: String
    let hint: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(Color(nsColor: Appearance.labelInk))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: Appearance.ink))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: Appearance.mutedInk))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 16)
                Text(hint)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Appearance.mutedInk))
            }
            .padding(.horizontal, 5.5)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: Appearance.hover).opacity(hovering ? 1 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The hover wash bleeds past the column so the icon lines up
        // with the section label.
        .padding(.horizontal, -5.5)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
    }
}

/// The badge in the window's bottom-left corner, out of the way of the
/// lists, shown only while a newer release is about. It is the one
/// coloured thing on the page, in the theme's accent. A ring fills as the
/// release downloads and installs itself; then a restart loop takes its
/// place, bobbing while the pointer rests on it, and a click relaunches.
/// After a failure a dotted arrow opens the browser download instead.
private struct UpdateBadge: View {
    let release: UpdateCheck.Release
    @ObservedObject private var updates = UpdateCheck.observed
    @State private var hovering = false
    @State private var shown = false
    @State private var bobbing = false

    private var clickable: Bool {
        switch updates.phase {
        case .ready, .failed: true
        case .found, .installing: false
        }
    }

    private var help: String {
        switch updates.phase {
        case .found, .installing: "Installing Papel \(release.version)…"
        case .ready: "Papel \(release.version) is ready. Click to restart"
        case .failed: "Couldn't install Papel \(release.version); click to download it"
        }
    }

    var body: some View {
        Button { UpdateCheck.activate(release) } label: {
            ZStack {
                switch updates.phase {
                case .found:
                    ProgressRing(fraction: 0)
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
private struct ProgressRing: View {
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
