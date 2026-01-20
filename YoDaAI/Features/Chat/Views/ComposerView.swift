import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Message composer view with text input, image handling, and toolbar
struct ComposerView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var viewModel: ChatViewModel
    let thread: ChatThread
    let providers: [LLMProvider]
    @Binding var showModelPicker: Bool
    @FocusState private var isFocused: Bool
    @State private var showFilePicker = false
    @ObservedObject private var scaleManager = AppScaleManager.shared

    private var defaultProvider: LLMProvider? {
        providers.first(where: { $0.isDefault }) ?? providers.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 8) {
                // Image thumbnails (if any)
                if !viewModel.pendingImages.isEmpty {
                    ImageThumbnailRow(viewModel: viewModel)
                    Divider()
                }

                // Mentioned apps chips
                if !viewModel.mentionedApps.isEmpty {
                    MentionChipsView(viewModel: viewModel)
                }

                // Text Input with popovers
                ZStack(alignment: .top) {
                    TextField("Ask anything, @ to mention apps, / for commands", text: $viewModel.composerText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...8)
                        .font(.system(size: 14 * scaleManager.scale))
                        .focused($isFocused)
                        .onChange(of: viewModel.composerText) { _, newValue in
                            // Check if user typed @
                            if newValue.hasSuffix("@") {
                                viewModel.showMentionPicker = true
                                viewModel.mentionSearchText = ""
                            }
                            // Check if user typed / for slash commands
                            viewModel.updateSlashCommandAutocomplete()
                        }
                        .onSubmit {
                            if !viewModel.composerText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty && !NSEvent.modifierFlags.contains(.shift) {
                                sendMessage()
                            }
                        }
                        .background(PasteInterceptor(onPaste: handleDirectPaste))
                        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                            return handleDrop(providers: providers)
                        }
                }
                .popover(isPresented: $viewModel.showMentionPicker, arrowEdge: .bottom) {
                    MentionPickerPopover(viewModel: viewModel)
                }
                .popover(isPresented: $viewModel.showSlashCommandPicker, arrowEdge: .bottom) {
                    SlashCommandPickerPopover(viewModel: viewModel)
                }

                // Toolbar row
                HStack(spacing: 16) {
                    // Left icons
                    HStack(spacing: 12) {
                        Button {
                            viewModel.showMentionPicker = true
                        } label: {
                            Image(systemName: "at")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(viewModel.mentionedApps.isEmpty ? Color.secondary : Color.accentColor)
                        .help("Add app context (@)")

                        Button {
                            viewModel.alwaysAttachAppContext.toggle()
                        } label: {
                            Image(systemName: viewModel.alwaysAttachAppContext ? "bolt.fill" : "bolt")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(viewModel.alwaysAttachAppContext ? .yellow : .secondary)
                        .help(viewModel.alwaysAttachAppContext ? "Auto-attach frontmost app: On" : "Auto-attach frontmost app: Off")

                        Button {
                            showFilePicker = true
                        } label: {
                            Image(systemName: "paperclip")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(viewModel.pendingImages.isEmpty ? .secondary : Color.accentColor)
                        .help("Attach image")
                        .fileImporter(
                            isPresented: $showFilePicker,
                            allowedContentTypes: [.image],
                            allowsMultipleSelection: true
                        ) { result in
                            handleFileSelection(result: result)
                        }
                    }

                    // Model selector (clickable)
                    Button {
                        showModelPicker.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text("/")
                                .foregroundStyle(.secondary)
                            Text(defaultProvider?.selectedModel ?? "No model")
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10 * scaleManager.scale))
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 13 * scaleManager.scale))
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showModelPicker, arrowEdge: .top) {
                        ModelPickerPopover(providers: providers)
                    }

                    Spacer()

                    // Send/Stop button
                    if viewModel.isSending {
                        // Stop button when sending
                        Button {
                            viewModel.stopGenerating()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Stop generating (Esc)")
                    } else {
                        // Send button when not sending
                        Button {
                            sendMessage()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
                        }
                        .buttonStyle(.borderless)
                        .disabled(!canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onKeyPress(.escape) {
            if viewModel.isSending {
                viewModel.stopGenerating()
                return .handled
            }
            return .ignored
        }
    }

    private var canSend: Bool {
        // Allow sending with images even if text is empty
        !viewModel.isSending && (!viewModel.composerText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty || !viewModel.pendingImages.isEmpty)
    }

    private func sendMessage() {
        guard canSend else { return }

        // Check if it's a slash command first
        if viewModel.executeSlashCommand(in: modelContext) {
            return  // Command was handled, don't send as message
        }

        // Remove trailing @ if user was about to mention
        if viewModel.composerText.hasSuffix("@") {
            viewModel.composerText = String(viewModel.composerText.dropLast())
        }
        viewModel.activeThreadID = thread.id
        viewModel.startSending(in: modelContext)
    }

    // MARK: - Image Handling

    /// Handle direct paste from pasteboard (Cmd+V)
    private func handleDirectPaste() {
        let pasteboard = NSPasteboard.general

        // Try to get image from pasteboard
        // Check for various image types that screenshots might use
        if let image = NSImage(pasteboard: pasteboard) {
            // Convert to PNG data
            if let pngData = image.pngData() {
                viewModel.addPendingImage(data: pngData, fileName: "pasted-image.png", mimeType: "image/png")
            }
        } else if let types = pasteboard.types,
                  types.contains(where: { $0.rawValue.contains("image") || $0.rawValue.contains("png") || $0.rawValue.contains("tiff") }) {
            // Fallback: try to read raw data
            for type in types {
                if let data = pasteboard.data(forType: type),
                   let image = NSImage(data: data),
                   let pngData = image.pngData() {
                    viewModel.addPendingImage(data: pngData, fileName: "pasted-image.png", mimeType: "image/png")
                    break
                }
            }
        }
    }

    /// Handle drag and drop
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    defer { group.leave() }
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.isFileURL else { return }
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            viewModel.addImagesFromURLs(urls)
        }

        return true
    }

    /// Handle file picker selection
    private func handleFileSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            viewModel.addImagesFromURLs(urls)
        case .failure(let error):
            viewModel.imageErrorMessage = "File selection error: \(error.localizedDescription)"
        }
    }
}
