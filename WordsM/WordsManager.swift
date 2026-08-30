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


    private let documentsURL: URL
    private let learnedURL: URL
    private let mistakesURL: URL

    // MARK: - Init

    init() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Cannot get documents directory")
        }
        self.documentsURL = docs
        self.learnedURL = docs.appendingPathComponent("learned.json")
        self.mistakesURL = docs.appendingPathComponent("mistakes.json")

        loadWords()
        loadLearned()
        loadMistakes()
    }

    // MARK: - Words

    private func loadWords() {
        guard let bundleURL = Bundle.main.url(forResource: "words", withExtension: "json") else {
            return
        }
        do {
            let data = try Data(contentsOf: bundleURL)
            let decoded = try JSONDecoder().decode([Word].self, from: data)
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

    func addToMistakes(_ id: Int) {
        mistakeIDs.insert(id)
        saveMistakes()
    }

    func removeFromMistakes(_ id: Int) {
        mistakeIDs.remove(id)
        saveMistakes()
    }

    private func saveMistakes() {
        let array = Array(mistakeIDs).sorted()
        save(array, to: mistakesURL)
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
