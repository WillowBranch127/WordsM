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
                        .font(.system(size: 36, weight: .bold))
                    Text(word.phonetic)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                    Text(word.pos)
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    Text(word.meaning)
                        .font(.system(size: 17))
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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                NavigationLink(destination: ContentView()) {
                    Label("退出", systemImage: "xmark.circle")
                }
            }
        }
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
