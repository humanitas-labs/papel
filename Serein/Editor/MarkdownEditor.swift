import AppKit
import SwiftUI

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = SereinTextView()

        textView.delegate = context.coordinator
        textView.string = text
        textView.syntaxStyler.apply(to: textView)

        scrollView.documentView = textView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Appearance.canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SereinTextView else { return }

        context.coordinator.text = $text

        guard textView.string != text else { return }
        let selection = textView.selectedRange()
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        textView.setSelectedRange(selection.clamped(to: text.utf16.count))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? SereinTextView else { return }
            text.wrappedValue = textView.string
            // Restyling replaces attributes across the whole storage. During
            // input-method composition that discards marked text, so styling
            // waits until the composition commits and fires a final change.
            guard !textView.hasMarkedText() else { return }
            textView.syntaxStyler.apply(to: textView)
        }
    }
}

extension NSRange {
    /// Clamps the range into `0...utf16Length` so a selection survives an
    /// external replacement of the text it referred to.
    func clamped(to utf16Length: Int) -> NSRange {
        let safeLocation = min(location, utf16Length)
        let availableLength = utf16Length - safeLocation
        return NSRange(location: safeLocation, length: min(length, availableLength))
    }
}

