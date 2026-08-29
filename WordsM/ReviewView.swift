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
        VStack(spacing: 0) {
            // 顶部标题栏
            headerView

            // 主要内容区（全屏单词卡片）
            VStack(spacing: 40) {
                // 题目区域 - 大字体居中
                questionView

                // 验证码式输入框（仅英文方向）
                if direction == .cnToEn && (state == .idle || state == .showingAnswer) {
                    captchaInputView
                }

                // 中文输入框（仅中文方向）
                if direction == .enToCn && (state == .idle || state == .showingAnswer) {
                    chineseInputView
                }

                Spacer()

                // 反馈区域（答题后显示）
                if let result = result {
                    feedbackView(result: result)
                }

                // AI 参考释义
                if let meaning = aiReferenceMeaning {
                    Text("参考释义：\(meaning)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }

                // 底部按钮区域
                bottomButtons
            }
            .padding(.vertical, 40)
        }
        .frame(minWidth: 440, maxWidth: 520, minHeight: 480, maxHeight: 560)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(mode == .learned ? "复习模式" : "错题本")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            NavigationLink(destination: ContentView()) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Question View

    private var questionView: some View {
        VStack(spacing: 16) {
            if direction == .cnToEn {
                // 看中文写英文：显示释义 + 词性（大字体）
                Text(word.meaning)
                    .font(.system(size: 28, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text(word.pos)
                    .font(.system(size: 16))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                // 看英文写中文：显示单词（超大字体）
                Text(word.word)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.primary)
                Text(word.phonetic)
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }

            // 如果显示答案，补充完整信息
            if state == .showingAnswer {
                Divider()
                    .padding(.vertical, 16)
                VStack(spacing: 12) {
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
    }

    // MARK: - Captcha Input View (英文验证码式输入)

    private var captchaInputView: some View {
        VStack(spacing: 12) {
            // 验证码格子
            HStack(spacing: 8) {
                ForEach(0..<max(word.word.count, userInput.count + 1), id: \.self) { index in
                    captchaCell(index: index)
                }
            }
            .padding(.horizontal, 40)

            // 隐藏的真实输入框（用于键盘输入）
            TextField("", text: $userInput)
                .opacity(0)
                .frame(width: 1, height: 1)
        }
        .padding(.top, 20)
    }

    private func captchaCell(index: Int) -> some View {
        let chars = Array(userInput)
        let char = index < chars.count ? String(chars[index]) : ""
        let isEmpty = char.isEmpty

        return VStack(spacing: 4) {
            // 字符显示区
            Text(char)
                .font(.system(size: 32, weight: .medium, design: .monospaced))
                .frame(width: 40, height: 48)
                .foregroundStyle(isEmpty ? .secondary : .primary)

            // 下划线
            Rectangle()
                .fill(Color.secondary.opacity(isEmpty ? 0.4 : 0.8))
                .frame(height: 2)
                .frame(maxWidth: .infinity)
        }
        .onTapGesture {
            // 点击格子时可以聚焦到隐藏输入框（可选）
        }
    }

    // MARK: - Chinese Input View

    private var chineseInputView: some View {
        VStack(spacing: 12) {
            TextEditor(text: $userInput)
                .font(.system(size: 20))
                .frame(minHeight: 100)
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
    }

    // MARK: - Feedback View

    private func feedbackView(result: QuizResult) -> some View {
        VStack(spacing: 12) {
            Image(systemName: result == .correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(result == .correct ? .green : .red)
            Text(result == .correct ? "回答正确！" : "回答错误")
                .font(.title2)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: 16) {
            switch state {
            case .idle, .showingAnswer:
                HStack(spacing: 16) {
                    if state == .showingAnswer {
                        Button("下一个") {
                            onNext()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    } else {
                        Button("不知道") {
                            onUnknown()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button(userInput.isEmpty ? "提交" : "下一个") {
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

            case .checking:
                ProgressView()

            case .result:
                VStack(spacing: 16) {
                    Button("下一个") {
                        onNext()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    if mode == .mistakes {
                        if result == .correct {
                            Button("移出错题本") {
                                onRemoveFromMistakes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        if result == .incorrect {
                            Button("加入错题本") {
                                onAddToMistakes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

            case .done:
                EmptyView()
            }
        }
        .padding(.horizontal, 40)
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
