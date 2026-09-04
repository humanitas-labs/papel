import SwiftUI

/// The corner badges' look: 12 pt rounded medium in the label ink on a
/// capsule of the code-block background. Zoom at the top right and the
/// file name at the top left share it so the two corners stay identical.
struct BadgePill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(Color(nsColor: Appearance.labelInk))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color(nsColor: Appearance.codeBlockBackground), in: Capsule())
            .contentShape(Capsule())
    }
}

extension View {
    func badgePill() -> some View { modifier(BadgePill()) }
}
