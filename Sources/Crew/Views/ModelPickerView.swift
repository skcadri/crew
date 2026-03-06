import SwiftUI

// MARK: - Model Definitions

struct ModelOption: Identifiable, Hashable {
    let id: String          // unique identifier / API value
    let displayName: String
    let provider: ModelProvider
}

enum ModelProvider: String, CaseIterable {
    case claudeCode = "Claude Code"
    case codex      = "Codex"
    case local      = "Local"
}

// MARK: - ModelPickerView

/// Dropdown picker grouped by provider (Claude Code / Codex / Local).
struct ModelPickerView: View {
    @Binding var selectedModel: String

    /// Dynamic local models injected from SettingsStore.
    var localModels: [String] = []

    // Static model catalogue
    private static let claudeModels: [ModelOption] = [
        ModelOption(id: "claude-sonnet-4-6",  displayName: "Sonnet 4.6",  provider: .claudeCode),
        ModelOption(id: "claude-opus-4-6",    displayName: "Opus 4.6",    provider: .claudeCode),
        ModelOption(id: "claude-haiku-4-5",   displayName: "Haiku 4.5",   provider: .claudeCode),
    ]

    private static let codexModels: [ModelOption] = [
        ModelOption(id: "gpt-5.3-codex", displayName: "GPT-5.3", provider: .codex),
        ModelOption(id: "codex-spark",   displayName: "Spark",   provider: .codex),
    ]

    private func localModelOptions() -> [ModelOption] {
        let dynamic = localModels.map {
            ModelOption(id: $0, displayName: $0, provider: .local)
        }
        return dynamic.isEmpty
            ? [ModelOption(id: "local-placeholder", displayName: "No local models found", provider: .local)]
            : dynamic
    }

    /// Find display name for the current selection.
    private var selectedDisplayName: String {
        let all = Self.claudeModels + Self.codexModels + localModelOptions()
        return all.first(where: { $0.id == selectedModel })?.displayName ?? selectedModel
    }

    var body: some View {
        Menu {
            // ── Claude Code ──────────────────────────────────────
            Section(ModelProvider.claudeCode.rawValue) {
                ForEach(Self.claudeModels) { model in
                    Button {
                        selectedModel = model.id
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if selectedModel == model.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            // ── Codex ────────────────────────────────────────────
            Section(ModelProvider.codex.rawValue) {
                ForEach(Self.codexModels) { model in
                    Button {
                        selectedModel = model.id
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if selectedModel == model.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            // ── Local ────────────────────────────────────────────
            Section(ModelProvider.local.rawValue) {
                ForEach(localModelOptions()) { model in
                    Button {
                        guard model.id != "local-placeholder" else { return }
                        selectedModel = model.id
                    } label: {
                        HStack {
                            Text(model.displayName)
                                .foregroundStyle(model.id == "local-placeholder" ? .secondary : .primary)
                            if selectedModel == model.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(model.id == "local-placeholder")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                Text(selectedDisplayName)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

#Preview {
    @Previewable @State var model = "claude-sonnet-4-6"
    ModelPickerView(selectedModel: $model, localModels: ["mistral-7b", "llama-3-8b"])
        .padding()
}
