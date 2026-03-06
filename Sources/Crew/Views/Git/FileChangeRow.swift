import SwiftUI

// MARK: - FileChangeRow

/// A single row in the Git file-change list.
/// Shows a colour-coded status badge, staging checkbox, and viewed state.
struct FileChangeRow: View {

    let change: FileChange
    @Binding var isChecked: Bool
    var isViewed: Bool = false
    var isSelected: Bool = false
    var onToggleViewed: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            // Staging checkbox
            Toggle(isOn: $isChecked) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            // Status badge
            statusBadge

            // Filename
            Text(displayName)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                .help(change.path)

            Spacer()

            if let onToggleViewed {
                Button(action: onToggleViewed) {
                    Image(systemName: isViewed ? "eye.fill" : "eye.slash")
                        .font(.caption)
                        .foregroundStyle(isViewed ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isViewed ? "Mark unviewed" : "Mark viewed")
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .cornerRadius(4)
    }

    // MARK: - Helpers

    private var displayName: String {
        URL(fileURLWithPath: change.path).lastPathComponent
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(badgeLabel)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(badgeColor, in: RoundedRectangle(cornerRadius: 3))
            .frame(minWidth: 18)
    }

    private var badgeLabel: String {
        switch change.status {
        case .modified:  return "M"
        case .added:     return "A"
        case .deleted:   return "D"
        case .untracked: return "?"
        case .renamed:   return "R"
        case .copied:    return "C"
        case .unknown:   return "~"
        }
    }

    private var badgeColor: Color {
        switch change.status {
        case .modified:  return .yellow
        case .added:     return .green
        case .deleted:   return .red
        case .untracked: return .gray
        case .renamed:   return .blue
        case .copied:    return .teal
        case .unknown:   return .gray
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 4) {
        FileChangeRow(
            change: FileChange(path: "Sources/Crew/Views/ContentView.swift", status: .modified),
            isChecked: .constant(true),
            isViewed: true,
            isSelected: true
        )
        FileChangeRow(
            change: FileChange(path: "Sources/Crew/NewFile.swift", status: .added),
            isChecked: .constant(false),
            isViewed: false
        )
    }
    .padding()
    .frame(width: 280)
}
#endif
