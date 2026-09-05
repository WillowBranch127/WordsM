import SwiftUI
import Combine
import UniformTypeIdentifiers

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
            let endpoint = URL(string: "\(baseURL)/models")!
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

// MARK: - Sync Result Toast

struct SyncResultToast: View {
    let message: String

    var body: some View {
        VStack(spacing: 4) {
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.05))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @EnvironmentObject var manager: WordsManager
    @StateObject private var syncManager: LANSyncManager
    @State private var showClearConfirm = false
    @State private var fileImporterShown = false
    @State private var importError = ""

    init(manager: WordsManager) {
        _syncManager = StateObject(wrappedValue: LANSyncManager(manager: manager))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
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

                Section("局域网同步") {
                    if syncManager.devices.isEmpty {
                        HStack {
                            ProgressView()
                            Text("正在扫描局域网...")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(syncManager.devices) { device in
                            let state = syncManager.syncStates[device.id] ?? .idle
                            HStack {
                                Text(device.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                syncButton(for: device, state: state)
                            }
                        }
                    }
                }

                Section("数据管理") {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("清空所有数据")
                            Spacer()
                            Text("将清除已学单词、错题本和错误次数记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("词库管理") {
                    Button {
                        fileImporterShown = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("导入自定义词库")
                            Spacer()
                            Text("JSON 格式，只需提供 word/phonetic/pos/meaning")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fileImporter(
                        isPresented: $fileImporterShown,
                        allowedContentTypes: [.json],
                        allowsMultipleSelection: true
                    ) { result in
                        switch result {
                        case .success(let urls):
                            var totalNew = 0
                            var totalSkip = 0
                            for url in urls {
                                let (newCount, skipCount) = importWords(from: url)
                                totalNew += newCount
                                totalSkip += skipCount
                            }
                            if totalNew > 0 {
                                importError = "成功导入 \(totalNew) 个新单词" + (totalSkip > 0 ? "，跳过 \(totalSkip) 个重复" : "")
                            } else if totalSkip > 0 {
                                importError = "所有 \(totalSkip) 个单词已在词库中"
                            }
                        case .failure(let error):
                            importError = "导入失败: \(error.localizedDescription)"
                        }
                    }
                    
                    if !importError.isEmpty {
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    if manager.customWords.count > 0 {
                        HStack {
                            Text("自定义词库: \(manager.customWords.count) 词")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("清除", role: .destructive) {
                                manager.customWords.removeAll()
                                manager.saveCustomWords()
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .confirmationDialog(
                "确认清空所有数据？",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("清空", role: .destructive) {
                    manager.clearAllData()
                }
                Button("取消", role: .cancel) {
                    // do nothing
                }
            } message: {
                Text("这将清除所有已学单词、错题本记录和错误次数，且无法恢复。")
            }
            .onAppear {
                syncManager.startDiscovery()
            }
            .onDisappear {
                syncManager.stopDiscovery()
            }
            .overlay(alignment: .bottom) {
                if let msg = syncManager.toastMessage {
                    SyncResultToast(message: msg)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                        .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Sync Button

    @ViewBuilder
    private func syncButton(for device: DiscoveredDevice, state: SyncUIState) -> some View {
        switch state {
        case .idle:
            Button("同步") {
                syncManager.sync(with: device.id)
            }
            .buttonStyle(.bordered)

        case .syncing:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .failed(let reason):
            Button {
                // Reset failed state
                // (syncStates is managed internally; tapping doesn't retry)
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .help(reason)
        }
    }

    /// 返回 (新增数量, 跳过数量)
    private func importWords(from url: URL) -> (newCount: Int, skipCount: Int) {
        do {
            let data = try Data(contentsOf: url)
            let words = try JSONDecoder().decode([Word].self, from: data)
            
            // 验证 word 字段不为空
            let validWords = words.filter { !$0.word.isEmpty }
            
            if validWords.count != words.count {
                return (0, 0)  // 无效词条由 importCustomWords 内部处理
            }
            
            let beforeCount = manager.customWords.count
            manager.importCustomWords(validWords)
            let afterCount = manager.customWords.count
            
            let newCount = afterCount - beforeCount
            let skipCount = words.count - newCount
            return (newCount, skipCount)
        } catch {
            return (0, 0)
        }
    }
}

// MARK: - Preview

    #Preview {
        SettingsView(manager: WordsManager())
    }
