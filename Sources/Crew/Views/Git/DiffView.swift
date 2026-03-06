import SwiftUI

// MARK: - DiffLine

/// Represents a single line in a unified diff.
struct DiffLine: Identifiable {
    enum Kind {
        case addition, deletion, context, header, fileHeader
    }

    /// Integer identity is cheaper than UUID for very large diffs.
    let id: Int
    let number: Int?          // line number (nil for headers)
    let content: String
    let kind: Kind
}

// MARK: - DiffParser

enum DiffParser {
    /// Parses raw unified diff text into an array of `DiffLine` values.
    /// Returns parse timing so callers can surface lightweight diagnostics.
    static func parseWithTiming(_ raw: String) -> (lines: [DiffLine], elapsedMs: Double) {
        let clock = ContinuousClock()
        let start = clock.now

        var result: [DiffLine] = []
        result.reserveCapacity(max(64, raw.utf8.count / 48))

        var lineNum = 0
        var addNum = 0
        var idx = 0

        // `split` is lighter than `components(separatedBy:)` for large payloads.
        for piece in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(piece)
            let kind: DiffLine.Kind
            let number: Int?

            if line.hasPrefix("diff --git") || line.hasPrefix("index ") ||
                line.hasPrefix("--- ") || line.hasPrefix("+++ ") ||
                line.hasPrefix("new file") || line.hasPrefix("deleted file") {
                kind = .fileHeader
                number = nil
            } else if line.hasPrefix("@@") {
                if let range = line.range(of: #"\+(\d+)"#, options: .regularExpression) {
                    let numStr = String(line[range]).dropFirst()
                    addNum = (Int(numStr) ?? 1) - 1
                    lineNum = addNum
                }
                kind = .header
                number = nil
            } else if line.hasPrefix("+") {
                addNum += 1
                kind = .addition
                number = addNum
            } else if line.hasPrefix("-") {
                lineNum += 1
                kind = .deletion
                number = lineNum
            } else {
                lineNum += 1
                addNum += 1
                kind = .context
                number = lineNum
            }

            result.append(DiffLine(id: idx, number: number, content: line, kind: kind))
            idx += 1
        }

        let elapsed = start.duration(to: clock.now)
        return (result, milliseconds(for: elapsed))
    }

    private static func milliseconds(for duration: Duration) -> Double {
        let comps = duration.components
        return (Double(comps.seconds) * 1_000) + (Double(comps.attoseconds) / 1_000_000_000_000_000)
    }
}

// MARK: - DiffView

/// Renders a unified diff with green additions, red deletions, and line numbers.
struct DiffView: View {

    let diffText: String
    var onParseMetrics: ((Double, Int) -> Void)? = nil

    @State private var lines: [DiffLine] = []

    var body: some View {
        Group {
            if diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState
            } else {
                diffContent
            }
        }
        .task(id: diffText) {
            let parsed = DiffParser.parseWithTiming(diffText)
            lines = parsed.lines
            onParseMetrics?(parsed.elapsedMs, parsed.lines.count)
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
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func diffRow(for line: DiffLine) -> some View {
        HStack(spacing: 0) {
            lineNumberGutter(for: line)

            Text(linePrefix(for: line))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(prefixColor(for: line))
                .frame(width: 16, alignment: .leading)
                .padding(.trailing, 2)

            Text(lineContent(for: line))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor(for: line))
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
        case .addition: return Color.green.opacity(0.15)
        case .deletion: return Color.red.opacity(0.15)
        case .header: return Color.blue.opacity(0.08)
        case .fileHeader: return Color.purple.opacity(0.08)
        case .context: return Color.clear
        }
    }

    private func textColor(for line: DiffLine) -> Color {
        switch line.kind {
        case .addition, .deletion, .context: return Color(nsColor: .controlTextColor)
        case .header: return .blue
        case .fileHeader: return .purple
        }
    }

    private func prefixColor(for line: DiffLine) -> Color {
        switch line.kind {
        case .addition: return .green
        case .deletion: return .red
        case .header: return .blue
        case .fileHeader: return .purple
        case .context: return .secondary
        }
    }

    private func linePrefix(for line: DiffLine) -> String {
        switch line.kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .header, .fileHeader, .context: return " "
        }
    }

    private func lineContent(for line: DiffLine) -> String {
        switch line.kind {
        case .addition, .deletion:
            return line.content.count > 1 ? String(line.content.dropFirst()) : ""
        default:
            return line.content.hasPrefix(" ") ? String(line.content.dropFirst()) : line.content
        }
    }
}

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
    -        Text(\"Hello, world!\")
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
