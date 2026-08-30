//
//  iOSApp.swift
//  WordsM iOS
//
//  Created by shuzhong liu on 2026/8/30.
//

import SwiftUI

@main
struct iOSApp: App {
    @StateObject private var wordsManager = WordsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(wordsManager)
        }
    }
}
