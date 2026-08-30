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

// MARK: - Mistake Cycle Round

enum MistakeCycleRound {
    case first
    case second
}

// MARK: - Review View Model

class ReviewViewModel: ObservableObject {
    @Published var currentWord: Word?
    @Published var direction: QuizDirection = .cnToEn
    @Published var state: QuizState = .idle
    @Published var userInput: String = ""
    @Published var result: QuizResult?
    @Published var aiReferenceMeaning: String?
    @Published var mistakeRemovedAfterWrong: Bool = false
    @Published var isLoadingAI: Bool = false

    let mode: ReviewMode
    let manager: WordsManager

    // MARK: - Shuffle State
    private var shuffleQueue: [Int] = []
    private var lastRoundOrder: [Int] = []
    private var mistakeLastRoundOrder: [Int] = []

    // MARK: - Mistake Cycle State
    @Published var isMistakeCycleFinished: Bool = false
    private var mistakeRound: MistakeCycleRound = .first
    private var firstRoundDirections: [Int: QuizDirection] = [:]
    private var mistakeShuffledIDs: [Int] = []

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
        switch mode {
        case .learned:
            loadLearnedNextWord()
        case .mistakes:
            loadMistakeNextWord()
        }
    }

    // MARK: - Learned Mode Word Loading

    private func loadLearnedNextWord() {
        let ids = manager.learnedIDs
        guard !ids.isEmpty else {
            currentWord = nil
            return
        }

        if shuffleQueue.isEmpty {
            repeat {
                shuffleQueue = ids.shuffled()
            } while shuffleQueue.count > 1 && shuffleQueue == lastRoundOrder
            lastRoundOrder = shuffleQueue
        }

        let candidateId = shuffleQueue.removeFirst()
        currentWord = manager.words.first { $0.id == candidateId }
        resetQuiz()
    }

    // MARK: - Mistake Mode Word Loading (Two-Round Cycle)
    // mistakeRound 始终表示"当前正在进行的轮次"，不在建队时提前切换。

    private func loadMistakeNextWord() {
        guard !isMistakeCycleFinished else { return }

        let currentIDs = manager.mistakeIDs

        // 尝试从当前轮队列取出下一题（跳过已移出错的题本的单词）
        while !mistakeShuffledIDs.isEmpty {
            let candidateId = mistakeShuffledIDs.removeFirst()
            guard currentIDs.contains(candidateId) else { continue }
            currentWord = manager.words.first { $0.id == candidateId }
            resetQuiz()
            return
        }

        // 当前轮队列已耗尽，判断进入下一轮还是结束大循环
        if mistakeRound == .first {
            startSecondMistakeRound(currentIDs: currentIDs)
        } else {
            finishMistakeCycle()
        }
    }

    // 建立第二轮队列：过滤掉中途移出的单词，方向全部取反
    private func startSecondMistakeRound(currentIDs: Set<Int>) {
        let stillValid = currentIDs.filter { firstRoundDirections[$0] != nil }
        if stillValid.isEmpty {
            finishMistakeCycle()
            return
        }
        repeat {
            mistakeShuffledIDs = stillValid.shuffled()
        } while mistakeShuffledIDs.count > 1 && mistakeShuffledIDs == mistakeLastRoundOrder
        mistakeLastRoundOrder = mistakeShuffledIDs
        mistakeRound = .second
        // 不立刻出题，交由 loadMistakeNextWord() 的 while 循环取第一题
    }

    // 两轮全部完成
    private func finishMistakeCycle() {
        isMistakeCycleFinished = true
        currentWord = nil
    }

    // MARK: - Reset Mistake Cycle

    func resetMistakeCycle() {
        mistakeRound = .first
        firstRoundDirections = [:]
        mistakeShuffledIDs = []
        isMistakeCycleFinished = false
        currentWord = nil
    }

    // MARK: - Opposite Direction

    private func oppositeDirection(_ direction: QuizDirection) -> QuizDirection {
        return direction == .cnToEn ? .enToCn : .cnToEn
    }


    func resetQuiz() {
        state = .idle
        userInput = ""
        result = nil
        aiReferenceMeaning = nil
        isLoadingAI = false
        mistakeRemovedAfterWrong = false

        if mode == .mistakes && currentWord != nil {
            // 错题本模式：方向由第一轮记录决定，第二轮取反
            if let savedDir = firstRoundDirections[currentWord!.id] {
                direction = mistakeRound == .first ? savedDir : oppositeDirection(savedDir)
            }
        } else {
            // 复习模式：随机分配方向
            direction = [.cnToEn, .enToCn].randomElement() ?? .cnToEn
        }
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
        guard let word = currentWord else { return }
        manager.addToMistakes(word.id)
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
        // 注意：不在此处调用 nextWord()，由 UI 层统一调用 onRemoveFromMistakes + onNext
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

        if !isCorrect {
            manager.addToMistakes(word.id)
        }
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
            // 未配置 AI，关键词交集 fallback
            let normalized = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let isReasonable = !normalized.isEmpty && normalized._keywordOverlap(wordMeaning: word.meaning)
            if !isReasonable {
                manager.addToMistakes(word.id)
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
                apiKey: apiKey,
                model: UserDefaults.standard.string(forKey: "wordsM_selectedModel") ?? "gpt-4"
            )
            print("[WordsM AI] word=\(word.word) input=\(userInput) isReasonable=\(response.isReasonable) ref=\(response.referenceMeaning)")
            aiReferenceMeaning = response.referenceMeaning
            if !response.isReasonable {
                manager.addToMistakes(word.id)
            }
            result = response.isReasonable ? .correct : .incorrect
            state = .result
        } catch {
            print("[WordsM AI] error: \(error)")
            // 网络失败，关键词交集 fallback
            let normalized = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let isReasonable = !normalized.isEmpty && normalized._keywordOverlap(wordMeaning: word.meaning)
            print("[WordsM AI] fallback(network error) word=\(word.word) input=\(userInput) isReasonable=\(isReasonable)")
            if !isReasonable {
                manager.addToMistakes(word.id)
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
    @StateObject private var viewModel: ReviewViewModel

    init(mode: ReviewMode, manager: WordsManager) {
        self.mode = mode
        _viewModel = StateObject(wrappedValue: ReviewViewModel(mode: mode, manager: manager))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 错题本大循环完成页面
            if mode == .mistakes && viewModel.isMistakeCycleFinished {
                MistakeCycleEndView(onRetry: viewModel.resetMistakeCycle, onExit: dismissAction)
            }
            // 答题区
            else if let word = viewModel.currentWord {
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
                    mistakeRemovedAfterWrong: $viewModel.mistakeRemovedAfterWrong,
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

    @Environment(\.dismiss) private var dismiss

    private func dismissAction() {
        dismiss()
    }
}

// MARK: - Quiz Card

struct QuizCard: View {
    let word: Word
    let mode: ReviewMode
    let direction: QuizDirection
    let state: QuizState
    @Binding var userInput: String
    @FocusState private var isTextFieldFocused: Bool
    var onSubmit: (() -> Void)?
    var onUnknown: (() -> Void)?
    var onNext: (() -> Void)?
    var onAddToMistakes: (() -> Void)?
    var onRemoveFromMistakes: (() -> Void)?
    @Binding var mistakeRemovedAfterWrong: Bool
    let result: QuizResult?
    let aiReferenceMeaning: String?
    let isLoadingAI: Bool

    var body: some View {
        VStack(spacing: 0) {
            titleHeader

            // 主体答题区
            VStack(spacing: 24) {
                questionView

                if direction == .cnToEn && (state == .idle || state == .showingAnswer) {
                    captchaInputView
                }

                if direction == .enToCn && (state == .idle || state == .showingAnswer) {
                    chineseInputView
                }

                Spacer()

                if let result = result {
                    feedbackView(result: result)
                }

                if let meaning = aiReferenceMeaning {
                    Text("参考释义：\(meaning)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }

                bottomButtons
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(minWidth: 440, maxWidth: 520, minHeight: 480, maxHeight: 560)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: word.word) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
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
    
    /// 验证码式输入框 - 完全自定义实现
    private var captchaInputView: some View {
        let charCount = word.word.count
        let itemWidth: CGFloat = 36   // 每个字母/下划线单元格的宽度
        let spacing: CGFloat = 12     // 格子之间的间距
        let totalWidth: CGFloat = CGFloat(charCount) * itemWidth + CGFloat(max(0, charCount - 1)) * spacing

        return ZStack {
            // 1. 底层视觉渲染层
            HStack(spacing: spacing) {
                ForEach(0..<charCount, id: \.self) { index in
                    VStack(spacing: 6) {
                        // 字符或光标
                        ZStack {
                            if index < userInput.count {
                                let charIndex = userInput.index(userInput.startIndex, offsetBy: index)
                                Text(String(userInput[charIndex]))
                                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.primary)
                            } else if index == userInput.count && state == .idle && isTextFieldFocused {
                                // 自定义伪光标
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: 2, height: 28)
                            } else {
                                Color.clear.frame(height: 28)
                            }
                        }
                        .frame(height: 36)

                        // 对应的下划线
                        Rectangle()
                            .fill(index <= userInput.count ? Color.blue : Color.secondary.opacity(0.4))
                            .frame(width: itemWidth, height: 3)
                            .cornerRadius(1.5)
                    }
                    .frame(width: itemWidth)
                }
            }

            // 2. 顶层：完全覆盖的透明 TextField 接收输入
            TextField("", text: $userInput)
                .focused($isTextFieldFocused)
                .textFieldStyle(.plain)
                .foregroundStyle(.clear) 
                .tint(.clear)
                .accentColor(.clear) 
                .opacity(0.01) 
                .disableAutocorrection(true)
                .frame(width: totalWidth, height: 50)
                .contentShape(Rectangle())
                .disabled(state == .result)
                .onSubmit {
                    if state == .idle {
                        onSubmit?()
                    } else {
                        onNext?()
                    }
                }
                .onChange(of: userInput) { _, newValue in
                    if newValue.count > charCount {
                        userInput = String(newValue.prefix(charCount))
                    }
                }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Chinese Input View

    private var chineseInputView: some View {
        ZStack {
            if userInput.isEmpty && state == .idle {
                Text("输入中文释义…")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
            TextField("", text: $userInput)
                .font(.system(size: 22, weight: .medium))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .focused($isTextFieldFocused)
                .disabled(state == .result)
                .onSubmit {
                    if state == .idle {
                        onSubmit?()
                    } else {
                        onNext?()
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .padding(.horizontal, 40)
        .padding(.top, 16)
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
                            onNext?()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    } else {
                        Button("不知道") {
                            onUnknown?()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button(userInput.isEmpty ? "提交" : "下一个") {
                            if state == .idle {
                                onSubmit?()
                            } else {
                                onNext?()
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
                        if mistakeRemovedAfterWrong {
                            onRemoveFromMistakes?()
                        }
                        onNext?()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    if mode == .mistakes && result == .correct {
                        Button("移出错题本") {
                            onRemoveFromMistakes?()
                            onNext?()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    } else if mode == .learned && result == .incorrect && !mistakeRemovedAfterWrong {
                        // 复习模式下答错自动加入错题本，显示"AI判错？移出错题本"按钮
                        Button("AI判错？移出错题本") {
                            mistakeRemovedAfterWrong = true
                            // 只标记状态，不立即切题，等用户点"下一个"
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    } else if mode == .learned && result == .incorrect && mistakeRemovedAfterWrong {
                        Text("已移出")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

            case .done:
                EmptyView()
            }
        }
        .padding(.horizontal, 40)
    }

    private var titleHeader: some View {
        Text(mode == .learned ? "复习模式" : "错题本")
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Mistake Cycle End View

struct MistakeCycleEndView: View {
    var onRetry: () -> Void
    var onExit: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("你已刷完一次错题本啦！")
                .font(.title2)
                .fontWeight(.semibold)
            HStack(spacing: 16) {
                Button("再来一轮") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button("退出") {
                    onExit()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 60)
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
        apiKey: String,
        model: String
    ) async throws -> AIResponse {
        let endpoint = URL(string: "\(baseURL.rstripSlash())/chat/completions")!

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": """
你是一名英语单词教学评估助手。判断用户写的中文释义是否合理。

判定标准：
- 用户答案与正确释义核心含义一致 → isReasonable: true
- 用户回答了同义词、近义词、或至少一个主要义项 → isReasonable: true
- 用户答案明显偏题、写了其他单词的释义 → isReasonable: false
- 用户答案过短、无意义（如"对"、"好"）或仅注音不含含义 → isReasonable: false

规则：
1. 多义词有多个义项（用分号或序号分隔），用户答出其中一个主要义项即算合理。
2. 用户答案可以比正确释义更口语化或更简洁，只要核心含义正确即可。
3. 义项顺序不同不算错，以含义匹配为准。
4. referenceMeaning 必须固定输出 word.meaning 的原始内容，不修改、不重写。
5. 只返回 JSON，不要包含任何其他文字或 markdown。
"""],
                ["role": "user", "content": """
请判断以下用户对英文单词的中文释义是否合理：

- 英文单词：\(word.word)
- 词性：\(word.pos)
- 正确释义：\(word.meaning)
- 用户回答：\(userInput)

只返回 JSON，格式为：{"isReasonable": true/false, "referenceMeaning": "<word的原始释义>"}
"""],
            ],
            "temperature": 0.1
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        print("[WordsM AI] REQUEST_BODY: \(String(data: request.httpBody!, encoding: .utf8) ?? "(nil)")")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "AIRequest", code: -1, userInfo: nil)
        }

        let rawText = String(data: data, encoding: .utf8) ?? "(empty)"
        print("[WordsM AI] RAW_RESPONSE: \(rawText)")

        // 从 OpenAI 兼容格式的 choices[0].message.content 中提取 AI 返回的 JSON
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let contentStr = message["content"] as? String {
            print("[WordsM AI] PARSED_CONTENT: \(contentStr)")
            // 优先用 JSONDecoder 解析完整 JSON
            if let respData = contentStr.data(using: .utf8),
               let resp = try? JSONDecoder().decode(AIResponse.self, from: respData) {
                return resp
            }
            // 容错：尝试从损坏的 JSON 字符串中提取 isReasonable
            let isReasonable: Bool
            if contentStr.contains("\"isReasonable\": true") {
                isReasonable = true
            } else if contentStr.contains("\"isReasonable\": false") {
                isReasonable = false
            } else {
                throw NSError(domain: "AIResponseParse", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "无法从 AI 响应中提取 isReasonable"])
            }
            // 提取 referenceMeaning：取 word.meaning 原始值作为 fallback
            return AIResponse(isReasonable: isReasonable, referenceMeaning: word.meaning)
        }
        throw NSError(domain: "AIResponseParse", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "AI 返回了非预期格式，无法解析 isReasonable"])
    }
}

// MARK: - String Extension

extension String {
    /// 判断用户输入与单词释义之间是否有足够的中文关键词交集
    func _keywordOverlap(wordMeaning: String) -> Bool {
        let inputTokens = self
            .components(separatedBy: CharacterSet.punctuationCharacters.union(.whitespaces))
            .filter { !$0.isEmpty }
        let meaningParts = wordMeaning
            .components(separatedBy: CharacterSet(charactersIn: "；,，。、"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let meaningTokens = meaningParts.joined(separator: " ")
            .components(separatedBy: CharacterSet.punctuationCharacters.union(.whitespaces))
            .filter { !$0.isEmpty }
        let hits = inputTokens.filter { meaningTokens.contains($0) }.count
        return hits >= (inputTokens.count >= 2 ? 2 : 1)
    }

    func rstripSlash() -> String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}

// MARK: - Preview

#Preview {
    ReviewView(mode: .learned, manager: WordsManager())
}
