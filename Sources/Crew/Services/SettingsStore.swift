import Foundation
import Security
import SwiftUI

// MARK: - Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

// MARK: - SettingsStore

/// Central preferences store.
/// Persists simple values in UserDefaults (@AppStorage) and
/// sensitive API keys in the macOS Keychain.
@MainActor
final class SettingsStore: ObservableObject {

    // MARK: Singleton

    static let shared = SettingsStore()

    // MARK: @AppStorage backed properties

    @AppStorage("defaultModel")    var defaultModel:    String = "claude-sonnet-4-6"
    @AppStorage("appTheme")        var theme:           String = AppTheme.system.rawValue
    @AppStorage("claudeCodePath")  var claudeCodePath:  String = "/usr/local/bin/claude"
    @AppStorage("lmStudioURL")     var lmStudioURL:     String = "http://127.0.0.1:1234"

    // MARK: Published

    @Published var lmStudioModels: [String] = []
    @Published var isTestingConnection: Bool = false
    @Published var connectionTestResult: Bool? = nil

    // MARK: Computed helpers

    var appTheme: AppTheme {
        get { AppTheme(rawValue: theme) ?? .system }
        set { theme = newValue.rawValue }
    }

    // MARK: Init

    private init() {}

    // MARK: - Keychain Helpers

    private enum KeychainKey: String {
        case openAIKey    = "com.crew.openai-api-key"
        case anthropicKey = "com.crew.anthropic-api-key"
    }

    // MARK: Write

    func saveToKeychain(key: String, service: String) -> Bool {
        let data = Data(key.utf8)

        // Delete any existing item first
        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    func readFromKeychain(service: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str  = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    // MARK: Convenience API key accessors

    var openAIKey: String {
        get { readFromKeychain(service: KeychainKey.openAIKey.rawValue) ?? "" }
        set { _ = saveToKeychain(key: newValue, service: KeychainKey.openAIKey.rawValue) }
    }

    var anthropicKey: String {
        get { readFromKeychain(service: KeychainKey.anthropicKey.rawValue) ?? "" }
        set { _ = saveToKeychain(key: newValue, service: KeychainKey.anthropicKey.rawValue) }
    }

    // MARK: - LM Studio

    /// Fetch available models from LM Studio's OpenAI-compatible endpoint.
    /// Returns `true` if the connection succeeded.
    func testLMStudioConnection() async -> Bool {
        isTestingConnection = true
        defer {
            Task { @MainActor in self.isTestingConnection = false }
        }

        guard let url = URL(string: lmStudioURL.trimmingCharacters(in: .whitespaces) + "/v1/models") else {
            connectionTestResult = false
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                connectionTestResult = false
                return false
            }

            // Parse {"object":"list","data":[{"id":"model-name",...}]}
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = json["data"] as? [[String: Any]] {
                let models = list.compactMap { $0["id"] as? String }
                await MainActor.run { self.lmStudioModels = models }
            }

            connectionTestResult = true
            return true
        } catch {
            connectionTestResult = false
            return false
        }
    }
}
