import SwiftUI
import Combine

// MARK: - Settings View Model

class SettingsViewModel: ObservableObject {
    @Published var baseURL: String = ""
    @Published var apiKey: String = ""

    private let baseURLKey = "wordsM_baseURL"
    private let apiKeyKey = "wordsM_apiKey"

    init() {
        baseURL = UserDefaults.standard.string(forKey: baseURLKey) ?? ""
        apiKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
    }

    func save() {
        UserDefaults.standard.set(baseURL, forKey: baseURLKey)
        UserDefaults.standard.set(apiKey, forKey: apiKeyKey)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()

    var body: some View {
        Form {
            Section("AI 配置") {
                LabeledContent("Base URL") {
                    TextField("", text: $vm.baseURL)
                        .textContentType(.URL)
                }

                LabeledContent("API Key") {
                    SecureField("", text: $vm.apiKey)
                        .textContentType(.password)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 220)
        .onChange(of: vm.baseURL) { _, _ in vm.save() }
        .onChange(of: vm.apiKey) { _, _ in vm.save() }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
