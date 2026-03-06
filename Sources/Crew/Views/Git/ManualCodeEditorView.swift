import SwiftUI
import AppKit
import Highlightr

struct ManualCodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let filePath: String
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = false
        textContainer.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = CGSize(width: 0, height: 0)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.apply(text: text, filePath: filePath, editable: isEditable)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(text: text, filePath: filePath, editable: isEditable)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ManualCodeEditorView
        weak var textView: NSTextView?
        private let highlightr: Highlightr? = {
            let instance = Highlightr()
            instance?.setTheme(to: "atom-one-dark")
            return instance
        }()
        private var isApplyingProgrammaticUpdate = false

        init(parent: ManualCodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate,
                  let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            highlightCurrentText(in: tv)
        }

        func apply(text: String, filePath: String, editable: Bool) {
            guard let tv = textView else { return }
            if tv.string != text || tv.isEditable != editable {
                isApplyingProgrammaticUpdate = true
                tv.isEditable = editable
                tv.isSelectable = true
                tv.allowsUndo = editable
                tv.string = text
                isApplyingProgrammaticUpdate = false
            }
            highlightCurrentText(in: tv)
        }

        private func highlightCurrentText(in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            let source = textView.string
            let language = languageForFile(path: parent.filePath)

            let highlighted = highlightr?.highlight(source, as: language)
                ?? NSAttributedString(string: source, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                ])

            isApplyingProgrammaticUpdate = true
            textView.textStorage?.setAttributedString(highlighted)
            let safeLocation = min(selectedRange.location, textView.string.count)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
            isApplyingProgrammaticUpdate = false
        }

        private func languageForFile(path: String) -> String {
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            switch ext {
            case "swift": return "swift"
            case "js", "mjs", "cjs": return "javascript"
            case "ts": return "typescript"
            case "tsx": return "tsx"
            case "jsx": return "jsx"
            case "py": return "python"
            case "rb": return "ruby"
            case "go": return "go"
            case "rs": return "rust"
            case "java": return "java"
            case "kt": return "kotlin"
            case "c", "h": return "c"
            case "cc", "cpp", "hpp": return "cpp"
            case "json": return "json"
            case "yml", "yaml": return "yaml"
            case "md": return "markdown"
            case "html": return "xml"
            case "css": return "css"
            case "sh", "zsh", "bash": return "bash"
            default: return "plaintext"
            }
        }
    }
}
