import SwiftUI
import Combine

// MARK: - Explore Mode

struct ExploreView: View {
    @EnvironmentObject var manager: WordsManager
    @State private var currentWord: Word?

    var body: some View {
        VStack {
            if let word = currentWord {
                VStack(spacing: 12) {
                    Text(word.word)
                        .font(.title)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                    Text(word.phonetic)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(word.pos)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    Text(word.meaning)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding()

                Spacer()

                Button("记住了，下一个") {
                    guard let w = currentWord else { return }
                    manager.markAsLearned(w.id)
                    loadNext()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("所有单词已学完！")
                        .font(.title2)
                    Text("你可以开始复习或查看错题本。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.bottom, 24)
        .onAppear { loadNext() }
    }

    private func loadNext() {
        currentWord = manager.randomUnlearnedWord()
    }
}

// MARK: - Preview

#Preview {
    ExploreView()
        .environmentObject(WordsManager())
}
