import SwiftUI

/// A single chat message bubble.
///
/// - User messages: right-aligned, blue background.
/// - Assistant messages: left-aligned, gray background with markdown rendering.
struct MessageBubble: View {

    let message: ChatMessage

    init(message: ChatMessage) {
        self.message = message
    }

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Bubble content

    @ViewBuilder
    private var bubbleContent: some View {
        if message.content.contains("```") {
            // Has code blocks — use custom markdown renderer
            MarkdownText(content: message.content, isUser: isUser)
        } else {
            // Plain text (may have **bold**)
            Text(styledText(message.content))
                .font(.body)
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Background

    private var bubbleBackground: some ShapeStyle {
        isUser
            ? AnyShapeStyle(Color.accentColor)
            : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Inline bold markdown

    /// Converts `**bold**` patterns to an AttributedString.
    private func styledText(_ raw: String) -> AttributedString {
        var attributed = AttributedString(raw)

        // Bold: **...** using NSRegularExpression to avoid regex literal issues
        let pattern = "\\*\\*(.+?)\\*\\*"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
            for match in matches {
                let nsRange = match.range
                if let attrRange = Range(nsRange, in: attributed) {
                    attributed[attrRange].font = .body.bold()
                }
            }
        }

        return attributed
    }
}

// MARK: - MarkdownText

/// Renders a string that may contain ``` code blocks using mixed SwiftUI views.
private struct MarkdownText: View {
    let content: String
    let isUser: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(segments, id: \.id) { segment in
                switch segment.kind {
                case .text(let str):
                    Text(str)
                        .font(.body)
                        .foregroundStyle(isUser ? Color.white : Color.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                case .code(let code, let lang):
                    CodeBlockView(code: code, language: lang)
                }
            }
        }
    }

    // MARK: Parsing

    private var segments: [Segment] {
        var result: [Segment] = []
        var remaining = content

        while !remaining.isEmpty {
            // Look for opening ```
            if let range = remaining.range(of: "```") {
                // Text before code block
                let before = String(remaining[remaining.startIndex..<range.lowerBound])
                if !before.isEmpty {
                    result.append(Segment(kind: .text(before)))
                }
                remaining = String(remaining[range.upperBound...])

                // Optional language specifier on same line
                var lang: String? = nil
                if let newline = remaining.firstIndex(of: "\n") {
                    let langStr = String(remaining[remaining.startIndex..<newline]).trimmingCharacters(in: .whitespaces)
                    if !langStr.isEmpty { lang = langStr }
                    remaining = String(remaining[remaining.index(after: newline)...])
                }

                // Find closing ```
                if let closeRange = remaining.range(of: "```") {
                    let code = String(remaining[remaining.startIndex..<closeRange.lowerBound])
                    result.append(Segment(kind: .code(code, lang)))
                    remaining = String(remaining[closeRange.upperBound...])
                } else {
                    // No closing ``` — treat rest as code
                    result.append(Segment(kind: .code(remaining, lang)))
                    remaining = ""
                }
            } else {
                result.append(Segment(kind: .text(remaining)))
                remaining = ""
            }
        }
        return result
    }

    struct Segment: Identifiable {
        let id = UUID()
        enum Kind {
            case text(String)
            case code(String, String?)
        }
        let kind: Kind
    }
}

// MARK: - CodeBlockView

/// A styled block for rendered code segments.
private struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label header
            if let lang = language {
                HStack {
                    Text(lang)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(nsColor: .separatorColor).opacity(0.3))
            }

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.trimmingCharacters(in: .newlines))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        MessageBubble(message: ChatMessage(
            worktreeId: UUID(),
            role: .user,
            content: "Can you show me a Swift example of a bubble sort?"
        ))
        MessageBubble(message: ChatMessage(
            worktreeId: UUID(),
            role: .assistant,
            content: "Sure! Here's a **bubble sort** in Swift:\n\n```swift\nfunc bubbleSort(_ arr: inout [Int]) {\n    for i in 0..<arr.count {\n        for j in 0..<arr.count - i - 1 {\n            if arr[j] > arr[j+1] {\n                arr.swapAt(j, j+1)\n            }\n        }\n    }\n}\n```\n\nThis runs in O(n²) time."
        ))
    }
    .frame(width: 600)
    .padding()
}
#endif
