import SwiftUI
import SwiftData

/// Chat header view with title and action buttons
struct ChatHeaderView: View {
    @Environment(\.modelContext) private var modelContext
    let thread: ChatThread
    let modelName: String
    var onClear: () -> Void

    @State private var showClearConfirmation = false
    @Environment(\.appScaleManager) private var scaleManager

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Text("C")
                        .font(.system(size: 13 * scaleManager.scale, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text(thread.title)
                    .font(.system(size: 14 * scaleManager.scale, weight: .semibold))
            }

            Spacer()

            Button {
                if thread.messages.isEmpty {
                    // Nothing to clear; no need to confirm.
                    return
                }
                showClearConfirmation = true
            } label: {
                Image(systemName: "eraser")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Clear Chat")
            .disabled(thread.messages.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("Clear Chat?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                onClear()
            }
        } message: {
            Text("This will delete all messages in \"\(thread.title)\". The chat itself is kept.")
        }
    }
}
