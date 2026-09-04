import SwiftUI

/// The view scale, as a percentage, in the window's top-right corner. It
/// shows for a moment whenever the zoom changes, comes back while the
/// pointer rests in that corner, and a click turns it into a field: type a
/// percentage and press Return to set the view to exactly that.
struct ZoomBadge: View {
    @ObservedObject private var zoom = Zoom.observed
    @ObservedObject private var store = ConfigurationStore.shared
    @State private var flashed = false
    @State private var zoneHovering = false
    @State private var pillHovering = false
    @State private var editing = false
    @State private var visible = false
    @State private var draft = ""
    @State private var hide: Task<Void, Never>?
    @State private var settle: Task<Void, Never>?
    @FocusState private var focused: Bool

    /// The pill, once shown, sits over the zone and takes the hover from
    /// it, so both report; either keeps the pill up, and a short grace
    /// before hiding rides over the hand-off.
    private var wanted: Bool { flashed || zoneHovering || pillHovering || editing }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // The hot zone: resting the pointer here brings the badge back.
            Color.clear
                .frame(width: 180, height: 64)
                .contentShape(Rectangle())
                .onHover { zoneHovering = $0 }
            pill
                .onHover { pillHovering = $0 }
                .padding(.top, 14)
                .padding(.trailing, 16)
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .animation(.easeInOut(duration: 0.18), value: visible)
        }
        .onChange(of: wanted, initial: true) { _, wanted in
            settle?.cancel()
            if wanted {
                visible = true
            } else {
                settle = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    visible = false
                }
            }
        }
        .onChange(of: zoom.scale) { _, _ in flash() }
        .onAppear { if zoom.scale != 1 { flash() } }
    }

    private var pill: some View {
        HStack(spacing: 1) {
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 34)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { end() }
                    .onChange(of: focused) { _, isFocused in if !isFocused { end() } }
            } else {
                Text("\(zoom.percent)")
            }
            Text("%")
        }
        .badgePill()
        .onTapGesture { if !editing { begin() } }
    }

    private func flash() {
        hide?.cancel()
        flashed = true
        hide = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            flashed = false
        }
    }

    private func begin() {
        draft = "\(zoom.percent)"
        editing = true
        focused = true
    }

    private func commit() {
        if let percent = Int(draft.trimmingCharacters(in: .whitespaces)) { Zoom.set(percent: percent) }
        end()
    }

    private func end() {
        editing = false
        focused = false
        flash()
    }
}

extension Zoom.Observed {
    var percent: Int { Int((scale * 100).rounded()) }
}
