import SwiftUI

// MARK: - SettingsView

/// App-level preferences window (⌘,).
/// Opened via `Settings` scene in `CrewApp.swift`.
struct SettingsView: View {

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("general")

            APIKeysSettingsView()
                .tabItem {
                    Label("API Keys", systemImage: "key.fill")
                }
                .tag("api-keys")
        }
        .frame(width: 480, height: 340)
    }
}

// MARK: - GeneralSettingsView

/// General tab: default model, theme, Claude Code binary path.
struct GeneralSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    @State private var selectedTheme: AppTheme = SettingsStore.shared.appTheme

    var body: some View {
        Form {
            // ── Default Model ─────────────────────────────────────
            Section {
                HStack {
                    Text("Default Model")
                    Spacer()
                    ModelPickerView(
                        selectedModel: $settings.defaultModel,
                        localModels:   settings.lmStudioModels
                    )
                }
            }

            // ── Appearance ────────────────────────────────────────
            Section {
                Picker("Theme", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedTheme) { _, newValue in
                    settings.appTheme = newValue
                    applyTheme(newValue)
                }
            } header: {
                Text("Appearance")
            }

            // ── Claude Code ───────────────────────────────────────
            Section {
                HStack {
                    TextField("Claude Code path", text: $settings.claudeCodePath)
                        .font(.system(.body, design: .monospaced))

                    Button("Browse…") {
                        pickClaudePath()
                    }
                }
            } header: {
                Text("Claude Code")
            } footer: {
                Text("Path to the `claude` CLI binary. Defaults to /usr/local/bin/claude.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectedTheme = settings.appTheme
        }
        .padding()
    }

    // MARK: Helpers

    private func applyTheme(_ theme: AppTheme) {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func pickClaudePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles    = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the claude CLI binary"
        if panel.runModal() == .OK, let url = panel.url {
            settings.claudeCodePath = url.path
        }
    }
}

// MARK: - APIKeysSettingsView

/// API Keys tab: OpenAI key, Anthropic key, LM Studio URL + test button.
struct APIKeysSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    @State private var openAIKey:    String = ""
    @State private var anthropicKey: String = ""
    @State private var testMessage:  String = ""

    var body: some View {
        Form {
            // ── OpenAI ────────────────────────────────────────────
            Section("OpenAI (Codex)") {
                SecureField("OpenAI API Key", text: $openAIKey)
                    .onSubmit { settings.openAIKey = openAIKey }
            }

            // ── Anthropic ─────────────────────────────────────────
            Section("Anthropic (Claude Code)") {
                SecureField("Anthropic API Key", text: $anthropicKey)
                    .onSubmit { settings.anthropicKey = anthropicKey }
            }

            // ── LM Studio ─────────────────────────────────────────
            Section {
                TextField("Base URL", text: $settings.lmStudioURL)
                    .font(.system(.body, design: .monospaced))

                HStack {
                    Button {
                        testMessage = ""
                        Task {
                            let ok = await settings.testLMStudioConnection()
                            testMessage = ok
                                ? "✓ Connected — \(settings.lmStudioModels.count) model(s) found"
                                : "✗ Connection failed"
                        }
                    } label: {
                        if settings.isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        }
                        Text("Test Connection")
                    }
                    .disabled(settings.isTestingConnection)

                    if !testMessage.isEmpty {
                        Text(testMessage)
                            .font(.caption)
                            .foregroundStyle(
                                testMessage.hasPrefix("✓") ? Color.green : Color.red
                            )
                    }
                }
            } header: {
                Text("LM Studio (Local Models)")
            } footer: {
                Text("LM Studio must be running on the specified URL.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openAIKey    = settings.openAIKey
            anthropicKey = settings.anthropicKey
        }
        .onChange(of: openAIKey)    { _, v in settings.openAIKey    = v }
        .onChange(of: anthropicKey) { _, v in settings.anthropicKey = v }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
