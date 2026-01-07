import Combine

@MainActor
final class SettingsRouter: ObservableObject {
    @Published var isPresented = false
    @Published var selectedTab: SettingsTab = .general

    enum SettingsTab: Hashable {
        case general
        case apiKeys
        case permissions
    }

    func open(_ tab: SettingsTab) {
        selectedTab = tab
        isPresented = true
    }
}
