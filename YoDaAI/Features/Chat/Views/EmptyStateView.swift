import SwiftUI

/// Empty state view shown when no thread is selected
struct EmptyStateView: View {
    @ObservedObject private var scaleManager = AppScaleManager.shared
    var onCreateNewChat: () -> Void
    var onOpenAPIKeysSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48 * scaleManager.scale))
                .foregroundStyle(.tertiary)

            Text("Start a Conversation")
                .font(.system(size: 22 * scaleManager.scale, weight: .medium))

            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Button("Click here to start") {
                        onCreateNewChat()
                    }
                    .buttonStyle(.link)

                    Text("or press Command + N")
                        .font(.system(size: 12 * scaleManager.scale))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Button("Open Settings") {
                        onOpenAPIKeysSettings()
                    }
                    .buttonStyle(.link)

                    Text("Shortcut: Command + ,")
                        .font(.system(size: 12 * scaleManager.scale))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
