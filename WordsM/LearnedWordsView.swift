import SwiftUI

// MARK: - LearnedWordsView

struct LearnedWordsView: View {
    @EnvironmentObject var manager: WordsManager
    @State private var searchText = ""

    var filteredWords: [Word] {
        let learned = manager.words
            .filter { manager.learnedIDs.contains($0.id) }
            .sorted { $0.word.lowercased() < $1.word.lowercased() }

        guard !searchText.isEmpty else { return learned }

        let query = searchText.lowercased()
        return learned.filter { word in
            word.word.lowercased().contains(query)
            || word.meaning.contains(searchText)
            || word.phonetic.lowercased().contains(query)
            || word.pos.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("已学单词")
                .toolbar {
#if os(iOS)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Text("\(filteredWords.count) 个")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
#endif
                }
                .searchable(text: $searchText, prompt: "搜索单词或释义")
        }
    }

    @ViewBuilder
    private var content: some View {
        if manager.learnedIDs.isEmpty {
            emptyView
        } else if filteredWords.isEmpty {
            noResultView
        } else {
            listContent
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("还没有已学单词")
                .font(.title2)
            Text("先在探索模式学习单词吧！")
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

    private var listContent: some View {
        List {
            ForEach(filteredWords) { word in
                WordRow(word: word, isInMistakes: manager.mistakeIDs.contains(word.id))
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#endif
    }
}

// MARK: - Word Row

struct WordRow: View {
    let word: Word
    let isInMistakes: Bool

    private let accentColor: Color = {
       #if os(iOS)
        return .red
        #else
        return .red
        #endif
    }()

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.word)
                    .font(.headline)
                    .foregroundStyle(isInMistakes ? accentColor : .primary)
                Text(word.phonetic)
                    .font(.caption)
                    .foregroundStyle(isInMistakes ? accentColor.opacity(0.7) : .secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(word.pos)
                    .font(.caption)
                    .foregroundStyle(isInMistakes ? accentColor : .blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(isInMistakes ? accentColor.opacity(0.1) : Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                Text(word.meaning)
                    .font(.caption)
                    .foregroundStyle(isInMistakes ? accentColor.opacity(0.85) : .secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    LearnedWordsView()
        .environmentObject(WordsManager())
}
