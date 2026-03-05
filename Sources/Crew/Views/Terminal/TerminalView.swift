import AppKit
import SwiftUI

// MARK: - TerminalView

/// An append-only terminal pane backed by NSTextView.
///
/// Features:
///   - SF Mono 11pt, dark (#1E1E1E) background, light (#D4D4D4) default text
///   - Append-only — not editable by the user
///   - Auto-scroll to bottom; disengages when the user scrolls up,
///     re-engages automatically when scrolled back to the bottom
///   - Standard macOS text selection + copy (⌘C)
///   - Renders attributed text from TerminalStore (ANSI colors pre-parsed)
public struct TerminalView: NSViewRepresentable {

    @ObservedObject public var store: TerminalStore

    public init(store: TerminalStore) {
        self.store = store
    }

    // MARK: - NSViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> NSScrollView {
        // ── Scroll view ──────────────────────────────────────────────────────
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = TerminalView.backgroundColor
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder

        // ── Text container + layout ──────────────────────────────────────────
        let containerSize = CGSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(containerSize: containerSize)
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        // ── Text view ─────────────────────────────────────────────────────────
        let textView = TerminalTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = CGSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.backgroundColor = TerminalView.backgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 6, height: 6)

        // Appearance
        textView.font = TerminalView.terminalFont
        textView.textColor = TerminalView.defaultTextColor

        // Interaction
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.usesFindBar = false
        textView.isRichText = false  // we manage attributes ourselves
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        scrollView.documentView = textView

        // ── Auto-scroll notifications ─────────────────────────────────────────
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleScrollEnd(_:)),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )

        context.coordinator.scrollView = scrollView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Replace text storage content with the store's attributed string
        let newText = store.text
        if let storage = textView.textStorage {
            // Only update if content actually changed (perf guard)
            if storage.string != newText.string || storage.length != newText.length {
                storage.setAttributedString(newText)
            }
        }

        // Auto-scroll to bottom if not manually paused
        if context.coordinator.autoScroll {
            scrollToBottom(scrollView)
        }
    }

    // MARK: - Scroll helpers

    private func scrollToBottom(_ scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.scrollToEndOfDocument(nil)
    }

    // MARK: - Constants

    static let backgroundColor = NSColor(red: 0x1E / 255.0,
                                         green: 0x1E / 255.0,
                                         blue: 0x1E / 255.0,
                                         alpha: 1.0)

    static let defaultTextColor = NSColor(red: 0xD4 / 255.0,
                                          green: 0xD4 / 255.0,
                                          blue: 0xD4 / 255.0,
                                          alpha: 1.0)

    static let terminalFont: NSFont =
        NSFont(name: "SF Mono", size: 11)
        ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    // MARK: - Coordinator

    public final class Coordinator: NSObject {
        /// Whether the view should auto-scroll on new content.
        var autoScroll: Bool = true

        /// Weak reference to the managed scroll view (for re-engagement checks).
        weak var scrollView: NSScrollView?

        /// User is actively scrolling — update auto-scroll flag.
        @objc func handleScroll(_ notification: Notification) {
            guard let sv = notification.object as? NSScrollView else { return }
            autoScroll = isScrolledToBottom(sv)
        }

        /// Scroll gesture ended — do a final check for re-engagement.
        @objc func handleScrollEnd(_ notification: Notification) {
            guard let sv = notification.object as? NSScrollView else { return }
            autoScroll = isScrolledToBottom(sv)
        }

        /// Returns true when the scroll position is at (or very near) the bottom.
        private func isScrolledToBottom(_ scrollView: NSScrollView) -> Bool {
            let clipView = scrollView.contentView
            let documentView = scrollView.documentView ?? clipView

            let visibleRect = clipView.documentVisibleRect
            let docHeight = documentView.frame.height
            let viewportBottom = visibleRect.origin.y + visibleRect.height

            // Allow 4pt tolerance for floating-point slop
            return viewportBottom >= docHeight - 4
        }
    }
}

// MARK: - TerminalTextView

/// Subclass that intercepts right-click to show a minimal copy menu and
/// suppresses any editing-related menu items.
private final class TerminalTextView: NSTextView {

    override var acceptsFirstResponder: Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copyItem = NSMenuItem(
            title: "Copy",
            action: #selector(copy(_:)),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = .command
        menu.addItem(copyItem)

        let selectAllItem = NSMenuItem(
            title: "Select All",
            action: #selector(selectAll(_:)),
            keyEquivalent: "a"
        )
        selectAllItem.keyEquivalentModifierMask = .command
        menu.addItem(selectAllItem)

        return menu
    }
}

// MARK: - Preview

#if DEBUG
struct TerminalView_Previews: PreviewProvider {
    static var previews: some View {
        let store = TerminalStore()
        Task { @MainActor in
            store.append("$ swift build\n")
            store.append("\u{1B}[32mBuild complete!\u{1B}[0m\n")
            store.append("\u{1B}[33mWarning: unused variable 'x'\u{1B}[0m\n")
            store.append("\u{1B}[31mError: file not found\u{1B}[0m\n")
            store.append("Normal output continues here...\n")
        }
        return TerminalView(store: store)
            .frame(width: 600, height: 300)
    }
}
#endif
