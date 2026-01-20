import SwiftUI
import SwiftData

/// Thread row view displayed in the sidebar
struct ThreadRowView: View {
    let thread: ChatThread
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        HStack(spacing: 10) {
            // Chat icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 28, height: 28)
                Text("C")
                    .font(.system(size: 13 * scaleManager.scale, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(thread.title)
                    .font(.system(size: 13.5 * scaleManager.scale, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(thread.createdAt, style: .date)
                    .font(.system(size: 11 * scaleManager.scale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
