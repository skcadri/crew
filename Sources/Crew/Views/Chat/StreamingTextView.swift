import AppKit
import SwiftUI

/// An `NSViewRepresentable` that wraps `NSTextView` for streaming agent text.
///
/// Text is appended incrementally via `appendText(_:)` on the coordinator,
/// and the view auto-scrolls to the bottom as new content arrives.
struct StreamingTextView: NSViewRepresentable {

    /// The full text to display. Binding allows the parent to push updates.
    @Binding var text: String

    init(text: Binding<String>) {
        self._text = text
    }

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let containerSize = CGSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        let textContainer = NSTextContainer(containerSize: containerSize)
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = CGSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // Appearance — matches the rest of the chat UI
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor

        // Non-editable, but selectable for copy/paste
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if text actually changed to avoid flicker
        if textView.string != text {
            textView.string = text
            // Auto-scroll to bottom when new content arrives
            textView.scrollToEndOfDocument(nil)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        /// Appends a chunk of text incrementally and scrolls to bottom.
        func appendText(_ chunk: String) {
            guard let textView = textView else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
            let attributed = NSAttributedString(string: chunk, attributes: attrs)
            textView.textStorage?.append(attributed)
            textView.scrollToEndOfDocument(nil)
        }
    }
}
