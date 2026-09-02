import AppKit

/// Supplies an undo manager to a test text view through the delegate, so
/// tests never need a window: a window's display cycle can reach
/// `PapelTextView` from AppKit while the test's task context is stale, and
/// the main-actor executor check then crashes the host.
@MainActor
final class TestUndoHost: NSObject, NSTextViewDelegate {
    let undoManager = UndoManager()

    func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

    /// Attaches to `textView` and enables undo.
    func attach(to textView: NSTextView) {
        textView.delegate = self
        textView.allowsUndo = true
    }
}
