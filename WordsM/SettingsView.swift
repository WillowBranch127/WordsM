import SwiftUI
import Combine

// MARK: - Settings View Model

class SettingsViewModel: ObservableObject {
    @Published var baseURL: String = ""
    @Published var apiKey: String = ""
    @Published var selectedModel: String = ""
    @Published var availableModels: [String] = []
    @Published var isFetchingModels: Bool = false
    @Published var fetchError: String?

    private let baseURLKey = "wordsM_baseURL"
    private let apiKeyKey = "wordsM_apiKey"
    private let selectedModelKey = "wordsM_selectedModel"

    init() {
        baseURL = UserDefaults.standard.string(forKey: baseURLKey) ?? ""
        apiKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
        selectedModel = UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
    }

    func save() {
        UserDefaults.standard.set(baseURL, forKey: baseURLKey)
        UserDefaults.standard.set(apiKey, forKey: apiKeyKey)
        UserDefaults.standard.set(selectedModel, forKey: selectedModelKey)
    }

    func fetchModels() async {
        guard !baseURL.isEmpty, !apiKey.isEmpty else {
            fetchError = "请先填写 Base URL 和 API Key"
            return
        }

        isFetchingModels = true
        fetchError = nil

        do {
            let endpoint = URL(string: "\(baseURL.rstripSlash())/models")!
            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw NSError(domain: "FetchModels", code: -1, userInfo: [NSLocalizedDescriptionKey: "请求失败"])
            }

            // 解析模型列表
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["data"] as? [[String: Any]] {
                availableModels = models.compactMap { $0["id"] as? String }
                // 如果当前选择的模型不在列表中，清空选择
                if !selectedModel.isEmpty && !availableModels.contains(selectedModel) {
                    selectedModel = ""
                }
            }
        } catch {
            fetchError = "获取模型列表失败: \(error.localizedDescription)"
            availableModels = []
        }

        isFetchingModels = false
        save()
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

            Section("模型选择") {
                HStack {
                    if vm.availableModels.isEmpty {
                        Text("未选择模型")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("模型", selection: $vm.selectedModel) {
                            Text("请选择模型").tag("")
                            ForEach(vm.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }

                    Button(action: {
                        Task {
                            await vm.fetchModels()
                        }
                    }) {
                        if vm.isFetchingModels {
                            ProgressView()
                        } else {
                            Text("从 API 获取")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.baseURL.isEmpty || vm.apiKey.isEmpty || vm.isFetchingModels)
                }

                if let error = vm.fetchError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 300)
        .onChange(of: vm.baseURL) { _, _ in vm.save() }
        .onChange(of: vm.apiKey) { _, _ in vm.save() }
        .onChange(of: vm.selectedModel) { _, _ in vm.save() }
        .onAppear {
            // 如果有保存的模型，确保它在列表中
            if !vm.selectedModel.isEmpty && vm.availableModels.isEmpty {
                Task {
                    await vm.fetchModels()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
