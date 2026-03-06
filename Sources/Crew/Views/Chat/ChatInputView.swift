import SwiftUI
import AppKit

/// The chat input bar: multi-line text field, Send button, and model name indicator.
///
/// - Enter sends the message.
/// - Shift+Enter inserts a newline.
/// - Disabled while the agent is processing (`isProcessing == true`).
struct ChatInputView: View {

    @Binding var text: String
    let isProcessing: Bool
    let isInputLocked: Bool
    let modelName: String?
    let pendingQuestionPrompt: String?
    let onSend: () -> Void

    init(
        text: Binding<String>,
        isProcessing: Bool,
        isInputLocked: Bool = false,
        modelName: String? = nil,
        pendingQuestionPrompt: String? = nil,
        onSend: @escaping () -> Void
    ) {
        self._text = text
        self.isProcessing = isProcessing
        self.isInputLocked = isInputLocked
        self.modelName = modelName
        self.pendingQuestionPrompt = pendingQuestionPrompt
        self.onSend = onSend
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            if let prompt = pendingQuestionPrompt {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                    Text("Awaiting answer: \(prompt)")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Multi-line input
                ChatTextEditor(
                    text: $text,
                    isDisabled: isProcessing || isInputLocked,
                    autoFocus: pendingQuestionPrompt != nil,
                    onSend: handleSend
                )
                .frame(minHeight: 36, maxHeight: 120)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .disabled(isProcessing || isInputLocked)

                // Send button
                Button(action: handleSend) {
                    Image(systemName: isProcessing ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !isProcessing)
                .keyboardShortcut(.return, modifiers: [])
                .help(isProcessing ? "Stop" : (pendingQuestionPrompt == nil ? "Send (Return)" : "Submit answer (Return)"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Model name indicator
            if let model = modelName, !model.isEmpty {
                HStack {
                    Image(systemName: "cpu")
                        .imageScale(.small)
                    Text(model)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing && !isInputLocked
    }

    private func handleSend() {
        guard canSend else { return }
        onSend()
    }
}

// MARK: - ChatTextEditor (NSViewRepresentable)

/// An NSTextView-backed multi-line editor that intercepts Return vs Shift+Return.
private struct ChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    let isDisabled: Bool
    let autoFocus: Bool
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSend: onSend)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear

        let textView = ChatNSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isVerticallyResizable = true
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        textView.delegate = context.coordinator
        textView.onSend = onSend

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Sync text from binding without triggering infinite loops
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = !isDisabled
        textView.alphaValue = isDisabled ? 0.5 : 1.0

        if autoFocus,
           !isDisabled,
           let window = textView.window,
           window.firstResponder !== textView {
            DispatchQueue.main.async {
                window.makeFirstResponder(textView)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSend: () -> Void
        weak var textView: NSTextView?

        init(text: Binding<String>, onSend: @escaping () -> Void) {
            self._text = text
            self.onSend = onSend
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
        }
    }
}

// MARK: - ChatNSTextView

/// NSTextView subclass that intercepts Return (send) vs Shift+Return (newline).
private final class ChatNSTextView: NSTextView {
    var onSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36  // kVK_Return
        let isShift  = event.modifierFlags.contains(.shift)

        if isReturn && !isShift {
            // Plain Return → send
            onSend?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    @Previewable @State var text = ""
    ChatInputView(
        text: $text,
        isProcessing: false,
        isInputLocked: false,
        modelName: "claude-sonnet-4",
        pendingQuestionPrompt: nil,
        onSend: { print("send: \(text)"); text = "" }
    )
    .frame(width: 600)
}
#endif
