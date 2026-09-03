import SwiftUI
import Combine

// MARK: - Word Model

struct Word: Codable, Identifiable {
    let id: Int
    let word: String
    let phonetic: String
    let pos: String
    let meaning: String
}

// MARK: - Words Manager

class WordsManager: ObservableObject {
    static let shared = WordsManager()

    @Published var words: [Word] = []
    @Published var learnedIDs: Set<Int> = []
    @Published var mistakeIDs: Set<Int> = []
    @Published var mistakeCounts: [Int: Int] = [:]  // 记录每个单词的错误次数

    private let documentsURL: URL
    private let learnedURL: URL
    private let mistakesURL: URL
    private let mistakeCountsURL: URL

    // MARK: - Init

    init() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Cannot get documents directory")
        }
        self.documentsURL = docs
        self.learnedURL = docs.appendingPathComponent("learned.json")
        self.mistakesURL = docs.appendingPathComponent("mistakes.json")
        self.mistakeCountsURL = docs.appendingPathComponent("mistake_counts.json")

        loadWords()
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

    func randomUnlearnedWord() -> Word? {
        let remaining = words.filter { !learnedIDs.contains($0.id) }
        guard !remaining.isEmpty else { return nil }
        return remaining.randomElement()
    }

    func randomLearnedWord() -> Word? {
        guard let id = learnedIDs.sorted().randomElement() else { return nil }
        return words.first { $0.id == id }
    }

    func randomMistakeWord() -> Word? {
        guard let id = mistakeIDs.sorted().randomElement() else { return nil }
        return words.first { $0.id == id }
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
