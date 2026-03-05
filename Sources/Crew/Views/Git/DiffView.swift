import SwiftUI

// MARK: - DiffLine

/// Represents a single line in a unified diff.
struct DiffLine: Identifiable {
    enum Kind {
        case addition, deletion, context, header, fileHeader
    }

    let id = UUID()
    let number: Int?          // line number (nil for headers)
    let content: String
    let kind: Kind
}

// MARK: - DiffParser

enum DiffParser {
    /// Parses raw unified diff text into an array of `DiffLine` values.
    static func parse(_ raw: String) -> [DiffLine] {
        var result: [DiffLine] = []
        var lineNum = 0
        var addNum  = 0

        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git") || line.hasPrefix("index ") ||
               line.hasPrefix("--- ") || line.hasPrefix("+++ ") ||
               line.hasPrefix("new file") || line.hasPrefix("deleted file") {
                result.append(DiffLine(number: nil, content: line, kind: .fileHeader))
            } else if line.hasPrefix("@@") {
                // Parse hunk header to get starting line numbers
                // Format: @@ -l,s +l,s @@
                if let range = line.range(of: #"\+(\d+)"#, options: .regularExpression) {
                    let numStr = String(line[range]).dropFirst()
                    addNum = (Int(numStr) ?? 1) - 1
                    lineNum = addNum
                }
                result.append(DiffLine(number: nil, content: line, kind: .header))
            } else if line.hasPrefix("+") {
                addNum += 1
                result.append(DiffLine(number: addNum, content: line, kind: .addition))
            } else if line.hasPrefix("-") {
                lineNum += 1
                result.append(DiffLine(number: lineNum, content: line, kind: .deletion))
            } else {
                lineNum += 1
                addNum  += 1
                result.append(DiffLine(number: lineNum, content: line, kind: .context))
            }
        }

        return result
    }
}

// MARK: - DiffView

/// Renders a unified diff with green additions, red deletions, and line numbers.
struct DiffView: View {

    let diffText: String

    private var lines: [DiffLine] {
        DiffParser.parse(diffText)
    }

    var body: some View {
        if diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyState
        } else {
            diffContent
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No diff available")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Select a file to view its changes")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Diff content

    private var diffContent: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    diffRow(for: line)
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func diffRow(for line: DiffLine) -> some View {
        HStack(spacing: 0) {
            // Line number gutter
            lineNumberGutter(for: line)

            // Diff prefix character (+/-/ )
            Text(linePrefix(for: line))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(prefixColor(for: line))
                .frame(width: 16, alignment: .leading)
                .padding(.trailing, 2)

            // Line content (strip the leading +/- for display)
            Text(lineContent(for: line))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor(for: line))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(rowBackground(for: line))
    }

    private func lineNumberGutter(for line: DiffLine) -> some View {
        Group {
            if let num = line.number {
                Text("\(num)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                    .padding(.trailing, 8)
            } else {
                Spacer()
                    .frame(width: 52)
            }
        }
    }

    // MARK: - Colour helpers

    private func rowBackground(for line: DiffLine) -> Color {
        switch line.kind {
        case .addition:  return Color.green.opacity(0.15)
        case .deletion:  return Color.red.opacity(0.15)
        case .header:    return Color.blue.opacity(0.08)
        case .fileHeader:return Color.purple.opacity(0.08)
        case .context:   return Color.clear
        }
    }

    private func textColor(for line: DiffLine) -> Color {
        switch line.kind {
        case .addition:  return Color(nsColor: .controlTextColor)
        case .deletion:  return Color(nsColor: .controlTextColor)
        case .header:    return .blue
        case .fileHeader:return .purple
        case .context:   return Color(nsColor: .controlTextColor)
        }
    }

    private func prefixColor(for line: DiffLine) -> Color {
        switch line.kind {
        case .addition:  return .green
        case .deletion:  return .red
        case .header:    return .blue
        case .fileHeader:return .purple
        case .context:   return .secondary
        }
    }

    private func linePrefix(for line: DiffLine) -> String {
        switch line.kind {
        case .addition:  return "+"
        case .deletion:  return "-"
        case .header,
             .fileHeader:return " "
        case .context:   return " "
        }
    }

    private func lineContent(for line: DiffLine) -> String {
        switch line.kind {
        case .addition, .deletion:
            // Strip leading +/- character already shown in prefix column
            return line.content.count > 1 ? String(line.content.dropFirst()) : ""
        default:
            return line.content.hasPrefix(" ") ? String(line.content.dropFirst()) : line.content
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let sampleDiff = """
    diff --git a/Sources/Crew/ContentView.swift b/Sources/Crew/ContentView.swift
    index abc1234..def5678 100644
    --- a/Sources/Crew/ContentView.swift
    +++ b/Sources/Crew/ContentView.swift
    @@ -1,8 +1,10 @@
     import SwiftUI
    -
    +import Combine
    +
     struct ContentView: View {
    -    var body: some View {
    -        Text("Hello, world!")
    +    @State private var selection: String? = nil
    +    var body: some View {
    +        NavigationSplitView {
    +            SidebarView()
         }
     }
    """
    DiffView(diffText: sampleDiff)
        .frame(width: 640, height: 400)
}
#endif
