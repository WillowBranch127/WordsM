import SwiftUI

// MARK: - LearnedWordsView

struct LearnedWordsView: View {
    @EnvironmentObject var manager: WordsManager

    var learnedWords: [Word] {
        manager.words
            .filter { manager.learnedIDs.contains($0.id) }
            .sorted { $0.word.lowercased() < $1.word.lowercased() }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("已学单词")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Text("\(learnedWords.count) 个")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if learnedWords.isEmpty {
            emptyView
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

    private var listContent: some View {
        List {
            ForEach(learnedWords) { word in
                WordRow(word: word)
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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.word)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(word.phonetic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(word.pos)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                Text(word.meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
