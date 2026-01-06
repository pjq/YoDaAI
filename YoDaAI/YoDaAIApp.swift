//
//  YoDaAIApp.swift
//  YoDaAI
//
//  Created by Peng, Jianqing on 2026/1/6.
//

import SwiftUI
import SwiftData

@main
struct YoDaAIApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ChatThread.self,
            ChatMessage.self,
            ProviderSettings.self,
            LLMProvider.self,
            AppPermissionRule.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
