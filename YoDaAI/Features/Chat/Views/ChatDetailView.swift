import SwiftUI
import SwiftData
import AppKit

/// Main chat detail view containing header, messages, and composer
struct ChatDetailView: View {
    @Environment(\.modelContext) private var modelContext

    var thread: ChatThread?
    @ObservedObject var viewModel: ChatViewModel
    var provider: LLMProvider?
    var providers: [LLMProvider]
    var onDeleteThread: () -> Void
    var onCreateNewChat: () -> Void
    var onOpenAPIKeysSettings: () -> Void

    @State private var showModelPicker = false
    @State private var showHelpAlert = false

    var body: some View {
        VStack(spacing: 0) {
            if let thread {
                // Header
                ChatHeaderView(
                    thread: thread,
                    modelName: provider?.selectedModel ?? "No model",
                    onDelete: onDeleteThread
                )

                Divider()

                // Messages
                MessageListView(thread: thread, viewModel: viewModel)

                // Composer
                ComposerView(
                    viewModel: viewModel,
                    thread: thread,
                    providers: providers,
                    showModelPicker: $showModelPicker
                )
            } else {
                EmptyStateView(onCreateNewChat: onCreateNewChat, onOpenAPIKeysSettings: onOpenAPIKeysSettings)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert("Error", isPresented: Binding(get: {
            viewModel.lastErrorMessage != nil
        }, set: { newValue in
            if !newValue { viewModel.lastErrorMessage = nil }
        })) {
            Button("OK", role: .cancel) {
                viewModel.lastErrorMessage = nil
            }
        } message: {
            Text(viewModel.lastErrorMessage ?? "Unknown error")
        }
        .alert("Image Error", isPresented: Binding(get: {
            viewModel.imageErrorMessage != nil
        }, set: { newValue in
            if !newValue { viewModel.imageErrorMessage = nil }
        })) {
            Button("OK", role: .cancel) {
                viewModel.imageErrorMessage = nil
            }
        } message: {
            Text(viewModel.imageErrorMessage ?? "Unknown error")
        }
        .alert("Commands", isPresented: $showHelpAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(SlashCommand.allCases.map { "\($0.displayName) - \($0.description)" }.joined(separator: "\n"))
        }
        .onAppear {
            setupCommandHandlers()
        }
    }

    private func setupCommandHandlers() {
        print("[SlashCommand] Setting up command handlers in ChatDetailView")

        // Help command - show alert with available commands
        viewModel.onHelpCommand = {
            print("[SlashCommand] Help handler called")
            DispatchQueue.main.async {
                showHelpAlert = true
            }
        }

        // Clear command - delete all messages in current thread
        viewModel.onClearCommand = {
            print("[SlashCommand] Clear handler called")
            guard let thread = thread else {
                print("[SlashCommand] Clear: thread is nil")
                return
            }
            let messageCount = thread.messages.count
            print("[SlashCommand] Clear: deleting \(messageCount) messages")

            // Delete all messages
            let messagesToDelete = Array(thread.messages)
            for message in messagesToDelete {
                modelContext.delete(message)
            }

            // Save changes
            do {
                try modelContext.save()
                print("[SlashCommand] Clear: successfully deleted \(messageCount) messages")
            } catch {
                print("[SlashCommand] Clear: error saving: \(error)")
            }
        }

        // New command - create new chat
        viewModel.onNewCommand = {
            print("[SlashCommand] New handler called")
            DispatchQueue.main.async {
                onCreateNewChat()
            }
        }

        // Models command - show model picker
        viewModel.onModelsCommand = {
            print("[SlashCommand] Models handler called")
            DispatchQueue.main.async {
                showModelPicker = true
            }
        }

        // Settings command - open settings window
        viewModel.onSettingsCommand = {
            print("[SlashCommand] Settings handler called")
            // Use the existing settings router to open settings
            // Need another async dispatch because settingsRouter.open() also modifies @Published properties
            DispatchQueue.main.async {
                onOpenAPIKeysSettings()
                print("[SlashCommand] Settings: Triggered settings window")
            }
        }

        // Copy command - copy conversation to clipboard
        viewModel.onCopyCommand = {
            print("[SlashCommand] Copy handler called")
            guard let thread = thread else {
                print("[SlashCommand] Copy: thread is nil")
                return
            }
            let text = thread.messages
                .sorted { $0.createdAt < $1.createdAt }
                .map { "\($0.role == .user ? "You" : "Assistant"): \($0.content)" }
                .joined(separator: "\n\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            print("[SlashCommand] Copy: copied \(text.count) characters to clipboard")
        }

        print("[SlashCommand] Command handlers setup complete")
    }
}
