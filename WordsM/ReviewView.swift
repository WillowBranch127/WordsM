import SwiftUI
import Combine

// MARK: - Review Mode

enum ReviewMode {
    case learned
    case mistakes
}

// MARK: - Quiz Direction

enum QuizDirection {
    case cnToEn   // 看中文写英文
    case enToCn   // 看英文写中文
}

// MARK: - Quiz State

enum QuizState {
    case idle           // 显示题目，等待输入
    case showingAnswer  // 点击"不知道"后展示完整信息
    case checking       // 提交答案，正在验证
    case result         // 显示对错结果
    case done           // 该题结束，等待"下一个"
}

// MARK: - Quiz Result

enum QuizResult {
    case correct
    case incorrect
    case skipped
}

// MARK: - Review View Model

class ReviewViewModel: ObservableObject {
    @Published var currentWord: Word?
    @Published var direction: QuizDirection = .cnToEn
    @Published var state: QuizState = .idle
    @Published var userInput: String = ""
    @Published var result: QuizResult?
    @Published var aiReferenceMeaning: String?
    @Published var isLoadingAI: Bool = false

    let mode: ReviewMode
    let manager: WordsManager

    // MARK: - Init

    init(mode: ReviewMode, manager: WordsManager) {
        self.mode = mode
        self.manager = manager
    }
    
    func loadWordIfNeeded() {
        guard currentWord == nil else { return }
        loadNextWord()
    }

    // MARK: - Word Loading

    func loadNextWord() {
        let word: Word?
        switch mode {
        case .learned:
            word = manager.randomLearnedWord()
        case .mistakes:
            word = manager.randomMistakeWord()
        }

        currentWord = word
        resetQuiz()
    }

    func resetQuiz() {
        state = .idle
        userInput = ""
        result = nil
        aiReferenceMeaning = nil
        isLoadingAI = false
        direction = .cnToEn
    }

    // MARK: - Actions

    func submitAnswer() {
        guard let word = currentWord else { return }

        state = .checking

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkAnswer(word)
        }
    }

    func showUnknown() {
        state = .showingAnswer
    }

    func nextWord() {
        loadNextWord()
    }

    func addToMistakes() {
        guard let word = currentWord else { return }
        manager.addToMistakes(word.id)
        nextWord()
    }

    func removeFromMistakes() {
        guard let word = currentWord else { return }
        manager.removeFromMistakes(word.id)
        nextWord()
    }

    // MARK: - Answer Checking

    private func checkAnswer(_ word: Word) {
        switch direction {
        case .cnToEn:
            checkEnglishAnswer(word)
        case .enToCn:
            checkChineseAnswer(word)
        }
    }

    private func checkEnglishAnswer(_ word: Word) {
        let isCorrect = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == word.word.lowercased()

        result = isCorrect ? .correct : .incorrect
        state = .result
    }

    private func checkChineseAnswer(_ word: Word) {
        Task {
            await callAI(word: word)
        }
    }

    // MARK: - AI Call

    private func callAI(word: Word) async {
        isLoadingAI = true

        let baseURL = UserDefaults.standard.string(forKey: "wordsM_baseURL") ?? ""
        let apiKey = UserDefaults.standard.string(forKey: "wordsM_apiKey") ?? ""

        if baseURL.isEmpty || apiKey.isEmpty {
            // 未配置 AI，使用简单匹配作为 fallback
            let isReasonable = word.meaning.contains(userInput)
                || userInput.split(separator: " ").allSatisfy { part in
                    word.meaning.contains(String(part))
                }
            result = isReasonable ? .correct : .incorrect
            state = .result
            isLoadingAI = false
            return
        }

        do {
            let response = try await AIHelper.checkChineseAnswer(
                word: word,
                userInput: userInput,
                baseURL: baseURL,
                apiKey: apiKey
            )
            aiReferenceMeaning = response.referenceMeaning
            result = response.isReasonable ? .correct : .incorrect
            state = .result
        } catch {
            // 网络失败，降级为简单匹配
            let isReasonable = word.meaning.contains(userInput)
                || userInput.split(separator: " ").allSatisfy { part in
                    word.meaning.contains(String(part))
                }
            result = isReasonable ? .correct : .incorrect
            state = .result
        }

        isLoadingAI = false
    }
}

// MARK: - Review View

struct ReviewView: View {
    let mode: ReviewMode
    @StateObject private var manager: WordsManager
    @StateObject private var viewModel: ReviewViewModel

    init(mode: ReviewMode) {
        self.mode = mode
        let wm = WordsManager()
        _manager = StateObject(wrappedValue: wm)
        _viewModel = StateObject(wrappedValue: ReviewViewModel(mode: mode, manager: wm))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(mode == .learned ? "复习模式" : "错题本")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                NavigationLink(destination: ContentView()) {
                    Label("退出", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            // 答题区
            if let word = viewModel.currentWord {
                QuizCard(
                    word: word,
                    mode: mode,
                    direction: viewModel.direction,
                    state: viewModel.state,
                    userInput: $viewModel.userInput,
                    onSubmit: viewModel.submitAnswer,
                    onUnknown: viewModel.showUnknown,
                    onNext: viewModel.nextWord,
                    onAddToMistakes: viewModel.addToMistakes,
                    onRemoveFromMistakes: viewModel.removeFromMistakes,
                    result: viewModel.result,
                    aiReferenceMeaning: viewModel.aiReferenceMeaning,
                    isLoadingAI: viewModel.isLoadingAI
                )
            } else {
                EmptyState(mode: mode)
            }
        }
        .frame(minWidth: 440, maxWidth: 520, minHeight: 480, maxHeight: 560)
        .onAppear { viewModel.loadWordIfNeeded() }
    }
}

// MARK: - Quiz Card

struct QuizCard: View {
    let word: Word
    let mode: ReviewMode
    let direction: QuizDirection
    let state: QuizState
    @Binding var userInput: String
    let onSubmit: () -> Void
    let onUnknown: () -> Void
    let onNext: () -> Void
    let onAddToMistakes: () -> Void
    let onRemoveFromMistakes: () -> Void
    let result: QuizResult?
    let aiReferenceMeaning: String?
    let isLoadingAI: Bool

    var body: some View {
        VStack(spacing: 16) {
            // 题目区域
            questionView

            // 输入区域
            if state == .idle || state == .showingAnswer {
                inputView
            }

            // 反馈区域
            if let result = result {
                feedbackView(result: result)
            }

            // AI 参考释义
            if let meaning = aiReferenceMeaning {
                Text("参考释义：\(meaning)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Spacer()

            // 按钮区域
            actionButtons
        }
        .padding()
    }

    // MARK: - Question View

    private var questionView: some View {
        VStack(spacing: 12) {
            if direction == .cnToEn {
                // 看中文写英文：显示释义 + 词性
                Text(word.meaning)
                    .font(.system(size: 18))
                    .multilineTextAlignment(.center)
                Text(word.pos)
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                // 看英文写中文：显示单词
                Text(word.word)
                    .font(.system(size: 32, weight: .bold))
                Text(word.phonetic)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            // 如果显示答案，补充完整信息
            if state == .showingAnswer {
                Divider()
                    .padding(.vertical, 8)
                VStack(spacing: 8) {
                    Text(word.word)
                        .font(.title)
                    Text(word.phonetic)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(word.pos)
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(word.meaning)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(spacing: 8) {
            if direction == .cnToEn {
                // 英文输入：带下划线
                HStack {
                    TextField("输入英文单词", text: $userInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20))
                        

                    // 下划线
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // 中文输入：多行文本框
                VStack {
                    TextEditor(text: $userInput)
                        .font(.body)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Feedback View

    private func feedbackView(result: QuizResult) -> some View {
        HStack {
            Image(systemName: result == .correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(result == .correct ? .green : .red)
            Text(result == .correct ? "回答正确！" : "回答错误")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            switch state {
            case .idle, .showingAnswer:
                // 提交或不知道
                HStack(spacing: 12) {
                    if state == .showingAnswer {
                        Button("下一个") {
                            onNext()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("不知道") {
                            onUnknown()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button(state == .idle ? "提交" : "下一个") {
                            if state == .idle {
                                onSubmit()
                            } else {
                                onNext()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.horizontal, 40)

            case .checking:
                ProgressView()
                    .padding()

            case .result:
                // 根据结果和模式显示不同按钮
                VStack(spacing: 12) {
                    Button("下一个") {
                        onNext()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 40)

                    if mode == .mistakes {
                        // 错题本：答对显示"移出错题本"
                        if result == .correct {
                            Button("移出错题本") {
                                onRemoveFromMistakes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .padding(.horizontal, 40)
                        }
                    } else {
                        // 复习模式：答错显示"加入错题本"
                        if result == .incorrect {
                            Button("加入错题本") {
                                onAddToMistakes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .padding(.horizontal, 40)
                        }
                    }
                }

            case .done:
                EmptyView()
            }
        }
    }
}

// MARK: - Empty State

struct EmptyState: View {
    let mode: ReviewMode

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: mode == .learned ? "book.open.fill" : "trash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(mode == .learned ? "没有已学单词" : "错题本为空")
                .font(.title2)
            Text(mode == .learned
                ? "请先在探索模式中学习一些单词"
                : "答错后会自动添加到错题本")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - AI Helper

struct AIHelper {
    struct AIResponse: Decodable {
        let isReasonable: Bool
        let referenceMeaning: String
    }

    static func checkChineseAnswer(
        word: Word,
        userInput: String,
        baseURL: String,
        apiKey: String
    ) async throws -> AIResponse {
        let endpoint = URL(string: "\(baseURL.rstripSlash())/chat/completions")!

        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": """
                你是一个中文释义判断助手。
                用户给出一个英文单词和其中文释义，你需要判断用户的回答是否合理。
                只返回 JSON：{"isReasonable": true/false, "referenceMeaning": "正确的中文释义"}
                """],
                ["role": "user", "content": """
                单词：\(word.word)
                用户回答：\(userInput)
                正确释义：\(word.meaning)
                """],
            ],
            "temperature": 0.1
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "AIRequest", code: -1, userInfo: nil)
        }

        let apiResponse = try JSONDecoder().decode(AIResponse.self, from: data)
        return apiResponse
    }
}

// MARK: - String Extension

extension String {
    func rstripSlash() -> String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}

// MARK: - Preview

#Preview {
    ReviewView(mode: .learned)
        .environmentObject(WordsManager())
}
