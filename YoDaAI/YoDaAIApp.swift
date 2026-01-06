//
//  YoDaAIApp.swift
//  YoDaAI
//
//  Created by Peng, Jianqing on 2026/1/6.
//

import SwiftUI
import SwiftData
import Combine

// MARK: - App Scale Manager
/// Manages the app-wide zoom/scale level with persistence
final class AppScaleManager: ObservableObject {
    static let shared = AppScaleManager()
    
    @Published var scale: CGFloat {
        didSet {
            UserDefaults.standard.set(scale, forKey: "app_scale")
        }
    }
    
    /// Available scale levels
    static let scaleLevels: [CGFloat] = [0.75, 0.85, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
    static let minScale: CGFloat = 0.75
    static let maxScale: CGFloat = 2.0
    static let defaultScale: CGFloat = 1.0
    
    private init() {
        self.scale = UserDefaults.standard.object(forKey: "app_scale") as? CGFloat ?? Self.defaultScale
    }
    
    func zoomIn() {
        // Find next larger scale level
        if let nextScale = Self.scaleLevels.first(where: { $0 > scale }) {
            scale = nextScale
        }
    }
    
    func zoomOut() {
        // Find next smaller scale level
        if let nextScale = Self.scaleLevels.last(where: { $0 < scale }) {
            scale = nextScale
        }
    }
    
    func resetZoom() {
        scale = Self.defaultScale
    }
    
    var scalePercentage: Int {
        Int(scale * 100)
    }
}

@main
struct YoDaAIApp: App {
    @StateObject private var scaleManager = AppScaleManager.shared
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ChatThread.self,
            ChatMessage.self,
            ProviderSettings.self,
            LLMProvider.self,
            AppPermissionRule.self,
            ImageAttachment.self,
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
                .scaleEffect(scaleManager.scale)
                .frame(
                    minWidth: 800 * scaleManager.scale,
                    minHeight: 600 * scaleManager.scale
                )
        }
        .modelContainer(sharedModelContainer)
        .commands {
            // View menu with zoom commands
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    scaleManager.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Zoom Out") {
                    scaleManager.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("Actual Size") {
                    scaleManager.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
                
                Divider()
                
                // Show current zoom level (non-interactive)
                Text("Zoom: \(scaleManager.scalePercentage)%")
            }
        }
    }
}
