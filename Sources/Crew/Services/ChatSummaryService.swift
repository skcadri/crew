import Foundation

struct ChatSummaryService {
    static let shared = ChatSummaryService()

    private let longChatMessageThreshold = 12
    private let longChatCharacterThreshold = 4_000
    private let minDeltaMessages = 4
    private let minDeltaCharacters = 1_200

    func shouldCreateSnapshot(messages: [ChatMessage], previous: ChatSummarySnapshot?) -> Bool {
        let messageCount = messages.count
        let characterCount = messages.reduce(into: 0) { $0 += $1.content.count }

        let longEnough = messageCount >= longChatMessageThreshold || characterCount >= longChatCharacterThreshold
        guard longEnough else { return false }

        guard let previous else { return true }

        let deltaMessages = messageCount - previous.messageCount
        let deltaCharacters = characterCount - previous.characterCount
        return deltaMessages >= minDeltaMessages || deltaCharacters >= minDeltaCharacters
    }

    func makeSnapshot(worktreeId: UUID, messages: [ChatMessage], previous: ChatSummarySnapshot?) -> ChatSummarySnapshot {
        let tocEntries = extractTOCEntries(from: messages)
        let summary = buildSummary(messages: messages, tocEntries: tocEntries)
        let messageCount = messages.count
        let characterCount = messages.reduce(into: 0) { $0 += $1.content.count }

        return ChatSummarySnapshot(
            id: previous?.id ?? UUID(),
            worktreeId: worktreeId,
            summary: summary,
            tocEntries: tocEntries,
            messageCount: messageCount,
            characterCount: characterCount,
            updatedAt: Date()
        )
    }

    func extractTOCEntries(from messages: [ChatMessage]) -> [ChatTOCEntry] {
        var entries: [ChatTOCEntry] = []

        for message in messages {
            let lines = message.content.components(separatedBy: .newlines)
            for (idx, rawLine) in lines.enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }

                if let heading = parseMarkdownHeading(line: line) {
                    entries.append(
                        ChatTOCEntry(
                            id: "\(message.id.uuidString)-h\(idx)",
                            title: heading.title,
                            level: heading.level,
                            messageId: message.id
                        )
                    )
                } else if let section = parseSectionHeading(line: line) {
                    entries.append(
                        ChatTOCEntry(
                            id: "\(message.id.uuidString)-s\(idx)",
                            title: section,
                            level: 2,
                            messageId: message.id
                        )
                    )
                }
            }
        }

        return dedupe(entries)
    }

    private func buildSummary(messages: [ChatMessage], tocEntries: [ChatTOCEntry]) -> String {
        guard !messages.isEmpty else { return "No chat activity yet." }

        let recentMessages = Array(messages.suffix(6))

        var lines: [String] = []
        lines.append("### Chat Summary")
        lines.append("- Total messages: \(messages.count)")

        if let latestUser = messages.last(where: { $0.role == .user }) {
            lines.append("- Latest user ask: \(compact(latestUser.content, max: 140))")
        }

        if let latestAssistant = messages.last(where: { $0.role == .assistant }) {
            lines.append("- Latest assistant response: \(compact(latestAssistant.content, max: 180))")
        }

        if !tocEntries.isEmpty {
            lines.append("- Key sections: \(tocEntries.prefix(5).map(\.title).joined(separator: ", "))")
        }

        lines.append("\n### Recent flow")
        for message in recentMessages {
            let prefix = message.role == .user ? "User" : "Assistant"
            lines.append("- **\(prefix):** \(compact(message.content, max: 120))")
        }

        return lines.joined(separator: "\n")
    }

    private func parseMarkdownHeading(line: String) -> (title: String, level: Int)? {
        guard line.hasPrefix("#") else { return nil }

        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }

        let title = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        return (String(title), hashes.count)
    }

    private func parseSectionHeading(line: String) -> String? {
        let pattern = "^(?:Section|Step|Phase)\\s+\\d+[\\.:\\-]?\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsrange = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: nsrange),
              let titleRange = Range(match.range(at: 1), in: line)
        else { return nil }

        let title = line[titleRange].trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    private func compact(_ content: String, max: Int) -> String {
        let oneLine = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.count <= max { return oneLine }
        return String(oneLine.prefix(max)) + "…"
    }

    private func dedupe(_ entries: [ChatTOCEntry]) -> [ChatTOCEntry] {
        var seen: Set<String> = []
        var result: [ChatTOCEntry] = []

        for entry in entries {
            let key = "\(entry.level)|\(entry.title.lowercased())|\(entry.messageId.uuidString)"
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(entry)
        }

        return result
    }
}
