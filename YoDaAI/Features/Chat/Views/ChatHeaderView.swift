import SwiftUI
import SwiftData

/// Chat header view with title and action buttons
struct ChatHeaderView: View {
    @Environment(\.modelContext) private var modelContext
    let thread: ChatThread
    let modelName: String
    var onDelete: () -> Void

    @State private var showDeleteConfirmation = false
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
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete Chat")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("Delete Chat?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will permanently delete \"\(thread.title)\" and all its messages.")
        }
    }
}
