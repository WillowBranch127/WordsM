import SwiftUI

// MARK: - CustomModeView

struct CustomModeView: View {
    @EnvironmentObject var manager: WordsManager
    @State private var searchText = ""
    @State private var selectedIDs: Set<Int> = []
    @State private var showReview = false

    // 保存/加载已选单词 ID
    private let selectedKey = "wordsM_customSelectedIDs"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索框 + 操作栏
                searchAndActionBar

                Divider()

                // 单词列表
                if manager.words.isEmpty {
                    emptyView
                } else if filteredWords.isEmpty {
                    noResultView
                } else {
                    listContent
                }

                // 底部操作栏
                if !manager.words.isEmpty {
                    bottomActionBar
                }
            }
            .navigationTitle("自定义模式")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(selectedIDs.count) 已选")
                        .font(.subheadline)
                        .foregroundStyle(selectedIDs.isEmpty ? Color.secondary : Color.blue)
                }
#endif
            }
            .onAppear(perform: loadSelected)
            .sheet(isPresented: $showReview) {
                ReviewView(mode: .custom, manager: manager, selectedIDs: selectedIDs)
            }
        }
    }

    // MARK: - Search and Action Bar (顶部)

    private var searchAndActionBar: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText)
            if !selectedIDs.isEmpty {
                HStack {
                    Text("已选 \(selectedIDs.count) 个单词")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        clearAllSelection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 12)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button {
                    clearAllSelection()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button {
                    showReview = true
                } label: {
                    Label("开始复习", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(selectedIDs.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Filtered Words

    private var filteredWords: [Word] {
        let query = searchText.lowercased()
        let allWords = manager.words.sorted { $0.word.lowercased() < $1.word.lowercased() }

        guard !query.isEmpty else { return allWords }

        return allWords.filter { word in
            word.word.lowercased().contains(query)
            || word.meaning.contains(searchText)
            || word.phonetic.lowercased().contains(query)
            || word.pos.lowercased().contains(query)
        }
    }

    // MARK: - List Content

    private var listContent: some View {
        List {
            // 先显示已学单词
            if let learnedSection = sectionForLearned {
                Section(learnedSection.title) {
                    ForEach(learnedSection.words) { word in
                        WordCheckRow(word: word, isSelected: selectedIDs.contains(word.id)) {
                            toggleSelect(word.id)
                        }
                    }
                }
            }

            // 再显示未学单词
            if let unlearnedSection = sectionForUnlearned {
                Section(unlearnedSection.title) {
                    ForEach(unlearnedSection.words) { word in
                        WordCheckRow(word: word, isSelected: selectedIDs.contains(word.id)) {
                            toggleSelect(word.id)
                        }
                    }
                }
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#endif
    }

    // MARK: - Sections

    private var sectionForLearned: (title: String, words: [Word])? {
        let learnedWords = manager.words
            .filter { manager.learnedIDs.contains($0.id) }
            .sorted { $0.word.lowercased() < $1.word.lowercased() }
        guard !learnedWords.isEmpty else { return nil }
        return ("已学单词 (\(learnedWords.count))", learnedWords)
    }

    private var sectionForUnlearned: (title: String, words: [Word])? {
        let unlearnedWords = manager.words
            .filter { !manager.learnedIDs.contains($0.id) }
            .sorted { $0.word.lowercased() < $1.word.lowercased() }
        guard !unlearnedWords.isEmpty else { return nil }
        return ("未学单词 (\(unlearnedWords.count))", unlearnedWords)
    }

    // MARK: - Actions

    private func toggleSelect(_ id: Int) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        saveSelected()
    }

    private func clearAllSelection() {
        selectedIDs.removeAll()
        saveSelected()
    }

    private func loadSelected() {
        if let data = UserDefaults.standard.data(forKey: selectedKey),
           let ids = try? JSONDecoder().decode([Int].self, from: data) {
            selectedIDs = Set(ids)
        }
    }

    private func saveSelected() {
        let array = Array(selectedIDs).sorted()
        if let data = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(data, forKey: selectedKey)
        }
    }

    // MARK: - Empty States

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("还没有单词")
                .font(.title2)
            Text("请先在探索模式学习单词")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
    }

    private var noResultView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("没有找到匹配的单词")
                .font(.title2)
            Text("试试其他关键词")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索单词或释义", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Word Check Row

struct WordCheckRow: View {
    let word: Word
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 勾选框
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .blue : .secondary)

                // 单词信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(word.word)
                            .font(.headline)
                        Text(word.phonetic)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(word.pos)
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Spacer()
                        Text(word.meaning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    CustomModeView()
        .environmentObject(WordsManager())
}
