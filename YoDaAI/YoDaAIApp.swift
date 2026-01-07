//
//  YoDaAIApp.swift
//  YoDaAI
//
//  Created by Peng, Jianqing on 2026/1/6.
//

import SwiftUI
import SwiftData
import Combine

// MARK: - App Text Scale Manager
/// Manages the app-wide text scale level with persistence
final class AppScaleManager: ObservableObject {
    static let shared = AppScaleManager()
    
    @Published var scale: CGFloat {
        didSet {
            UserDefaults.standard.set(scale, forKey: "app_text_scale")
        }
    }
    
    /// Available scale levels (as multipliers for base font size)
    static let scaleLevels: [CGFloat] = [0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0]
    static let minScale: CGFloat = 0.8
    static let maxScale: CGFloat = 2.0
    static let defaultScale: CGFloat = 1.0
    
    private init() {
        self.scale = UserDefaults.standard.object(forKey: "app_text_scale") as? CGFloat ?? Self.defaultScale
    }
    
    func zoomIn() {
        if let nextScale = Self.scaleLevels.first(where: { $0 > scale }) {
            scale = nextScale
        }
    }
    
    func zoomOut() {
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

// MARK: - Scaled Font View Modifier
/// Applies text scale to all text in the view hierarchy
struct ScaledFontModifier: ViewModifier {
    @ObservedObject var scaleManager = AppScaleManager.shared
    
    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.font) { font in
                // This doesn't work well, so we use a different approach
            }
    }
}

// MARK: - Custom Text View with Scaling
/// A Text view that automatically scales based on AppScaleManager
struct ScaledText: View {
    let content: String
    let baseSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    @ObservedObject private var scaleManager = AppScaleManager.shared
    
    init(_ content: String, size: CGFloat = 14, weight: Font.Weight = .regular, design: Font.Design = .default) {
        self.content = content
        self.baseSize = size
        self.weight = weight
        self.design = design
    }
    
    var body: some View {
        Text(content)
            .font(.system(size: baseSize * scaleManager.scale, weight: weight, design: design))
    }
}

@main
struct YoDaAIApp: App {
    @StateObject private var scaleManager = AppScaleManager.shared
    @StateObject private var settingsRouter = SettingsRouter()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ChatThread.self,
            ChatMessage.self,
            ProviderSettings.self,
            LLMProvider.self,
            AppPermissionRule.self,
            ImageAttachment.self,
            MCPServer.self,
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
                .environmentObject(scaleManager)
                .environmentObject(settingsRouter)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            // View menu with zoom commands
            CommandGroup(after: .toolbar) {
                Button("Increase Text Size") {
                    scaleManager.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Decrease Text Size") {
                    scaleManager.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("Actual Text Size") {
                    scaleManager.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
                
                Divider()
                
                Text("Text Size: \(scaleManager.scalePercentage)%")
            }
        }
    }
}
