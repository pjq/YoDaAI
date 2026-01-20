import SwiftUI
import AppKit

/// Horizontal scroll view showing pending images above composer
struct ImageThumbnailRow: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.pendingImages) { image in
                    ImageThumbnailView(image: image, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

/// Individual image thumbnail with remove button
struct ImageThumbnailView: View {
    let image: ChatViewModel.PendingImage
    @ObservedObject var viewModel: ChatViewModel
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail
            if let thumbnail = image.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            // Remove button (on hover)
            if isHovering {
                Button {
                    viewModel.removePendingImage(image)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .background(Circle().fill(Color.red))
                }
                .buttonStyle(.plain)
                .offset(x: 8, y: -8)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
