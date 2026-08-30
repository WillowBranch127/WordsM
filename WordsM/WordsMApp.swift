import SwiftUI
import Combine

@main
struct WordsMApp: App {
    @StateObject private var wordsManager = WordsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(wordsManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        Settings {
            SettingsView()
                .environmentObject(wordsManager)
        }
    }
}
