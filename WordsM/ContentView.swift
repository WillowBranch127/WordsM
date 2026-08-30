import SwiftUI
import Combine

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var manager: WordsManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("WordsM")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("辅助背单词")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)
                .padding(.bottom, 36)

                VStack(spacing: 16) {
                    CustomNavLink(destination: ExploreView()) {
                        ActionButton(icon: "magnifyingglass", title: "探索模式", subtitle: "随机浏览新单词")
                    }

                    CustomNavLink(destination: ReviewView(mode: .learned, manager: manager)) {
                        ActionButton(icon: "arrow.triangle.2.circlepath", title: "复习模式", subtitle: "主动回忆已学单词")
                    }

                    CustomNavLink(destination: ReviewView(mode: .mistakes, manager: manager)) {
                        ActionButton(icon: "book.fill", title: "错题本", subtitle: "\(manager.mistakeIDs.count) 个待复习")
                    }
                }
                .padding(.horizontal, 40)

                Spacer()

                HStack {
                    StatChip(icon: "checkmark.circle", label: "已学", value: "\(manager.learnedIDs.count)")
                    Spacer()
                    StatChip(icon: "xmark.circle", label: "错题", value: "\(manager.mistakeIDs.count)")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
            }
            .frame(minWidth: 440, maxWidth: 520, minHeight: 480, maxHeight: 560)
#if os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView()
                            .environmentObject(manager)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
#endif
        }
    }
}

// MARK: - Custom Nav Link

struct CustomNavLink<Destination: View, Label: View>: View {
    let destinationBuilder: () -> Destination
    let labelBuilder: () -> Label

    init(destination: @autoclosure @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.destinationBuilder = destination
        self.labelBuilder = label
    }

    var body: some View {
        NavigationLink(destination: destinationBuilder(), label: labelBuilder)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
#if os(iOS)
            .background(#if os(iOS)
            Color(.controlBackgroundColor)
        #else
            Color(NSColor.controlBackgroundColor)
        #endif)
#else
            .background(Color(NSColor.controlBackgroundColor))
#endif
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Chip

struct StatChip: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text("\(label) \(value)")
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(WordsManager())
}
