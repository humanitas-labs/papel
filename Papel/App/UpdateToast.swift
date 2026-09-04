import SwiftUI

/// The note after an update: "Papel" over "Updated to 0.7.0", in a pill at
/// the bottom left of the first window after the relaunch, in the accent
/// for the version. It fades in, stays a few seconds, and fades out; a
/// click dismisses it early.
struct UpdateToast: View {
    @ObservedObject private var updates = UpdateCheck.observed
    @ObservedObject private var store = ConfigurationStore.shared
    @State private var visible = false
    @State private var hide: Task<Void, Never>?

    var body: some View {
        Group {
            if let version = updates.justUpdatedTo {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Papel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: Appearance.ink))
                    Text("Updated to \(version)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: Appearance.accent))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(nsColor: Appearance.codeBlockBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(nsColor: Appearance.thematicBreakInk), lineWidth: 1))
                .padding(.bottom, 16)
                .padding(.leading, 16)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 6)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .onAppear {
                    withAnimation(.easeOut(duration: 0.35)) { visible = true }
                    hide = Task {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        dismiss()
                    }
                }
            }
        }
    }

    private func dismiss() {
        hide?.cancel()
        withAnimation(.easeIn(duration: 0.3)) { visible = false }
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            updates.justUpdatedTo = nil
        }
    }
}
