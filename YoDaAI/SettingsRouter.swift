import Combine

@MainActor
final class SettingsRouter: ObservableObject {
    @Published var isPresented = false
    @Published var selectedTab: SettingsTab = .general

    enum SettingsTab: Hashable {
        case general
        case apiKeys
        case mcpServers
        case permissions
    }

    func open(_ tab: SettingsTab) {
        // Defer state changes to avoid "Publishing changes during view update" errors
        Task { @MainActor in
            selectedTab = tab
            isPresented = true
        }
    }
}
