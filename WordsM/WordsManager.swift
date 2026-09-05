import SwiftUI
import Combine

// MARK: - Word Model

struct Word: Codable, Identifiable {
    var id: Int
    let word: String
    let phonetic: String
    let pos: String
    let meaning: String
}

// MARK: - Words Manager

class WordsManager: ObservableObject {
    static let shared = WordsManager()

    @Published var words: [Word] = []
    @Published var customWords: [Word] = []
    @Published var importSourceURLs: [URL] = []  // 记录导入的文件路径
    @Published var learnedIDs: Set<Int> = []
    @Published var mistakeIDs: Set<Int> = []
    @Published var mistakeCounts: [Int: Int] = [:]  // 记录每个单词的错误次数

    private let documentsURL: URL
    private let learnedURL: URL
    private let mistakesURL: URL
    private let mistakeCountsURL: URL
    private let customWordsURL: URL

    // MARK: - Init

    init() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Cannot get documents directory")
        }
        self.documentsURL = docs
        self.learnedURL = docs.appendingPathComponent("learned.json")
        self.mistakesURL = docs.appendingPathComponent("mistakes.json")
        self.mistakeCountsURL = docs.appendingPathComponent("mistake_counts.json")
        self.customWordsURL = docs.appendingPathComponent("custom_words.json")

        loadWords()
        loadCustomWords()
        loadLearned()
        loadMistakes()
        loadMistakeCounts()
    }

    // MARK: - Words

    private func loadWords() {
        guard let bundleURL = Bundle.main.url(forResource: "words", withExtension: "json") else {
            print("[WordsManager] words.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: bundleURL)
            let decoded = try JSONDecoder().decode([Word].self, from: data)
            print("[WordsManager] words loaded: \(decoded.count)")
            DispatchQueue.main.async {
                self.words = decoded
            }
        } catch {
            print("[WordsManager] Failed to load words: \(error)")
        }
    }

    func loadCustomWords() {
        guard let data = try? Data(contentsOf: customWordsURL) else { 
            customWords = []
            return 
        }
        do {
            let decoded = try JSONDecoder().decode([Word].self, from: data)
            print("[WordsManager] custom words loaded: \(decoded.count)")
            DispatchQueue.main.async {
                self.customWords = decoded
            }
        } catch {
            print("[WordsManager] Failed to load custom words: \(error)")
            customWords = []
        }
    }

    func importCustomWords(_ newWords: [Word], sourceURL: URL? = nil) {
        // 记录导入源
        if let url = sourceURL {
            if !importSourceURLs.contains(url) {
                importSourceURLs.append(url)
            }
        }
        
        // 获取当前所有词库（内置 + 自定义）的最大 id
        let allWords = getCombinedWords()
        let maxId = allWords.map { $0.id }.max() ?? 0
        
        // 建立现有自定义词库的映射（按 word 匹配）
        var existingByWord: [String: Int] = [:]
        for word in customWords {
            existingByWord[word.word.lowercased()] = word.id
        }
        
        // 建立结果映射
        var resultMap: [Int: Word] = [:]
        
        // 先加入所有现有的自定义词
        for word in customWords {
            resultMap[word.id] = word
        }
        
        // 处理新导入的词
        var nextId = maxId + 1
        for word in newWords {
            let wordKey = word.word.lowercased()
            
            if let existingId = existingByWord[wordKey] {
                // 如果已有相同单词，保留原 id，更新内容
                var updatedWord = word
                updatedWord.id = existingId
                resultMap[existingId] = updatedWord
            } else {
                // 新单词，分配新 id
                var newWord = word
                newWord.id = nextId
                resultMap[nextId] = newWord
                nextId += 1
            }
        }
        
        customWords = Array(resultMap.values).sorted { $0.word.lowercased() < $1.word.lowercased() }
        saveCustomWords()
        print("[WordsManager] custom words imported: \(customWords.count) total")
    }

    func saveCustomWords() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(customWords)
            try data.write(to: customWordsURL)
        } catch {
            print("[WordsManager] Save custom words failed: \(error)")
        }
    }

    func removeImportSource(_ url: URL) {
        // 获取该文件中的单词
        guard let data = try? Data(contentsOf: url) else { return }
        guard let words = try? JSONDecoder().decode([Word].self, from: data) else { return }
        
        // 找出这些单词在自定义词库中的 ID
        let idsToRemove = Set(words.compactMap { word in
            customWords.first(where: { $0.word.lowercased() == word.word.lowercased() })?.id
        })
        
        // 从自定义词库中移除
        customWords.removeAll { word in idsToRemove.contains(word.id) }
        saveCustomWords()
        
        // 移除记录
        importSourceURLs.removeAll { $0 == url }
        print("[WordsManager] removed import source: \(url.lastPathComponent), remaining custom words: \(customWords.count)")
    }

    // MARK: - Learned

    func loadLearned() {
        guard let data = try? Data(contentsOf: learnedURL) else { return }
        do {
            let ids = try JSONDecoder().decode([Int].self, from: data)
            DispatchQueue.main.async {
                self.learnedIDs = Set(ids)
            }
        } catch {
            print("[WordsManager] Failed to load learned: \(error)")
        }
    }

    func markAsLearned(_ id: Int) {
        learnedIDs.insert(id)
        saveLearned()
    }

    private func saveLearned() {
        let array = Array(learnedIDs).sorted()
        save(array, to: learnedURL)
    }

    // MARK: - Mistakes

    func loadMistakes() {
        guard let data = try? Data(contentsOf: mistakesURL) else { return }
        do {
            let ids = try JSONDecoder().decode([Int].self, from: data)
            DispatchQueue.main.async {
                self.mistakeIDs = Set(ids)
            }
        } catch {
            print("[WordsManager] Failed to load mistakes: \(error)")
        }
    }

    func loadMistakeCounts() {
        guard let data = try? Data(contentsOf: mistakeCountsURL) else { return }
        do {
            let counts = try JSONDecoder().decode([Int: Int].self, from: data)
            DispatchQueue.main.async {
                self.mistakeCounts = counts
            }
        } catch {
            print("[WordsManager] Failed to load mistake counts: \(error)")
        }
    }

    func addToMistakes(_ id: Int) {
        mistakeIDs.insert(id)
        saveMistakes()
        incrementMistakeCount(id)
    }

    func incrementMistakeCount(_ id: Int) {
        mistakeCounts[id, default: 0] += 1
        saveMistakeCounts()
    }

    func getMistakeCount(_ id: Int) -> Int {
        return mistakeCounts[id, default: 0]
    }

    func removeFromMistakes(_ id: Int) {
        mistakeIDs.remove(id)
        saveMistakes()
    }

    private func saveMistakes() {
        let array = Array(mistakeIDs).sorted()
        save(array, to: mistakesURL)
    }

    private func saveMistakeCounts() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(mistakeCounts)
            try data.write(to: mistakeCountsURL)
        } catch {
            print("[WordsManager] Save mistake counts failed: \(error)")
        }
    }

    // MARK: - LAN Sync Merge API

    /// Merges remote learned and mistake IDs into local state via union.
    /// Returns the count of newly added IDs for each category.
    @discardableResult
    func mergeSyncedData(
        remoteLearnedIDs: Set<Int>,
        remoteMistakeIDs: Set<Int>
    ) -> SyncMergeResult {
        let oldLearned = learnedIDs
        let oldMistakes = mistakeIDs

        learnedIDs.formUnion(remoteLearnedIDs)
        mistakeIDs.formUnion(remoteMistakeIDs)

        saveLearned()
        saveMistakes()

        let addedLearned = learnedIDs.subtracting(oldLearned).count
        let addedMistakes = mistakeIDs.subtracting(oldMistakes).count

        return SyncMergeResult(addedLearnedCount: addedLearned, addedMistakeCount: addedMistakes)
    }

    // MARK: - Clear All Data

    func clearAllData() {
        learnedIDs.removeAll()
        mistakeIDs.removeAll()
        mistakeCounts.removeAll()
        saveLearned()
        saveMistakes()
        saveMistakeCounts()
    }

    // MARK: - Helpers

    func getCombinedWords() -> [Word] {
        var map: [Int: Word] = [:]
        for word in words {
            map[word.id] = word
        }
        for word in customWords {
            map[word.id] = word
        }
        return Array(map.values).sorted { $0.word.lowercased() < $1.word.lowercased() }
    }

    func randomUnlearnedWord() -> Word? {
        let combined = getCombinedWords()
        let remaining = combined.filter { !learnedIDs.contains($0.id) }
        guard !remaining.isEmpty else { return nil }
        return remaining.randomElement()
    }

    func randomLearnedWord() -> Word? {
        guard let id = learnedIDs.sorted().randomElement() else { return nil }
        return getCombinedWords().first { $0.id == id }
    }

    func randomMistakeWord() -> Word? {
        guard let id = mistakeIDs.sorted().randomElement() else { return nil }
        return getCombinedWords().first { $0.id == id }
    }

    private func save(_ array: [Int], to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(array)
            try data.write(to: url)
        } catch {
            print("[WordsManager] Save failed: \(error)")
        }
    }
}
