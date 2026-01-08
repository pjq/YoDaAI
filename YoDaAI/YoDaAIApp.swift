//
//  YoDaAIApp.swift
//  YoDaAI
//
//  Created by Peng, Jianqing on 2026/1/6.
//

import SwiftUI
import SwiftData
import Combine
import ApplicationServices

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

// MARK: - App State (shared across app)
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var isSending: Bool = false
    private init() {}
}

@main
struct YoDaAIApp: App {
    @StateObject private var scaleManager = AppScaleManager.shared
    @StateObject private var settingsRouter = SettingsRouter()
    @StateObject private var appState = AppState.shared

    init() {
        // Request Accessibility permission on first launch
        requestAccessibilityPermissionOnStartup()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ChatThread.self,
            ChatMessage.self,
            ProviderSettings.self,
            LLMProvider.self,
            AppPermissionRule.self,
            ImageAttachment.self,
            AppContextAttachment.self,
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
            // Replace default "New Window" (Cmd+N) with "New Chat"
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(name: .createNewChat, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.isSending) // Disable during API calls
            }
            
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
        
        // Settings window (Cmd+,)
        Settings {
            AppSettingsView()
                .environmentObject(settingsRouter)
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Notification for New Chat
extension Notification.Name {
    static let createNewChat = Notification.Name("createNewChat")
}

// MARK: - Accessibility Permission Helper
/// Request Accessibility permission on app startup
private func requestAccessibilityPermissionOnStartup() {
    // Check if permission is already granted
    if AXIsProcessTrusted() {
        print("[YoDaAI] Accessibility permission already granted")
        return
    }

    // Check if this is first launch (no previous permission request)
    let hasRequestedBefore = UserDefaults.standard.bool(forKey: "hasRequestedAccessibilityPermission")

    if !hasRequestedBefore {
        print("[YoDaAI] First launch - requesting Accessibility permission")
        UserDefaults.standard.set(true, forKey: "hasRequestedAccessibilityPermission")

        // Request permission with prompt
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options)
    } else {
        print("[YoDaAI] Accessibility permission not granted - user needs to enable manually in System Settings")
    }
}

// MARK: - App Settings View (for Settings scene)
struct AppSettingsView: View {
    @EnvironmentObject private var settingsRouter: SettingsRouter
    @StateObject private var viewModel = ChatViewModel(
        accessibilityService: AccessibilityService(),
        permissionsStore: AppPermissionsStore()
    )
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            SettingsTabBar(selectedTab: $settingsRouter.selectedTab)
            
            Divider()
            
            // Tab content
            Group {
                switch settingsRouter.selectedTab {
                case .general:
                    GeneralSettingsContent(viewModel: viewModel)
                case .apiKeys:
                    APIKeysSettingsContent()
                case .mcpServers:
                    MCPServersSettingsContent()
                case .permissions:
                    PermissionsSettingsContent()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 650, height: 500)
    }
}

// MARK: - Custom Settings Tab Bar
struct SettingsTabBar: View {
    @Binding var selectedTab: SettingsRouter.SettingsTab
    
    var body: some View {
        HStack(spacing: 24) {
            SettingsTabButton(
                tab: .general,
                selectedTab: $selectedTab,
                icon: "gear",
                title: "General"
            )
            
            SettingsTabButton(
                tab: .apiKeys,
                selectedTab: $selectedTab,
                icon: "key",
                title: "API Keys"
            )
            
            SettingsTabButton(
                tab: .mcpServers,
                selectedTab: $selectedTab,
                icon: "server.rack",
                title: "MCP Servers"
            )
            
            SettingsTabButton(
                tab: .permissions,
                selectedTab: $selectedTab,
                icon: "lock.shield",
                title: "Permissions"
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
    }
}

// MARK: - Settings Tab Button
struct SettingsTabButton: View {
    let tab: SettingsRouter.SettingsTab
    @Binding var selectedTab: SettingsRouter.SettingsTab
    let icon: String
    let title: String
    
    private var isSelected: Bool {
        selectedTab == tab
    }
    
    var body: some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                    }
                    
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                .frame(width: 36, height: 36)
                
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle()) // Make entire area clickable
        }
        .buttonStyle(.plain)
    }
}
