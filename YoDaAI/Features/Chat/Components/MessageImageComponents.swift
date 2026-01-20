import SwiftUI
import AppKit

// MARK: - Message Image Grid View

/// Grid view for displaying image attachments in messages
struct MessageImageGridView: View {
    let attachments: [ImageAttachment]
    let alignment: HorizontalAlignment
    @State private var loadedImages: [UUID: NSImage] = [:]
    @State private var previewImage: NSImage?
    @State private var showPreview = false

    var body: some View {
        HStack {
            if alignment == .trailing {
                Spacer(minLength: 0)
            }

            VStack(alignment: alignment == .trailing ? .trailing : .leading, spacing: 8) {
                ForEach(attachments) { attachment in
                    if let image = loadedImages[attachment.id] {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 300, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .onTapGesture {
                                previewImage = image
                                showPreview = true
                            }
                            .help("Click to view full size")
                    } else {
                        ProgressView()
                            .frame(width: 150, height: 150)
                    }
                }
            }

            if alignment == .leading {
                Spacer(minLength: 0)
            }
        }
        .task {
            await loadImages()
        }
        .onChange(of: showPreview) { _, isShowing in
            if isShowing, let image = previewImage {
                showImagePreviewWindow(image: image)
            }
        }
    }

    private func showImagePreviewWindow(image: NSImage) {
        let previewWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        previewWindow.backgroundColor = .black
        previewWindow.isOpaque = false
        previewWindow.level = .floating
        previewWindow.isMovableByWindowBackground = false

        let hostingView = NSHostingView(rootView: ImagePreviewView(image: image, onClose: {
            previewWindow.close()
            showPreview = false
        }))
        previewWindow.contentView = hostingView
        previewWindow.center()
        previewWindow.makeKeyAndOrderFront(nil)
    }

    private func loadImages() async {
        for attachment in attachments {
            do {
                let data = try ImageStorageService.shared.loadImage(filePath: attachment.filePath)
                if let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        loadedImages[attachment.id] = nsImage
                    }
                }
            } catch {
                print("Failed to load image: \(error)")
            }
        }
    }
}

// MARK: - Image Preview View

/// Full-screen image preview with zoom support
struct ImagePreviewView: View {
    let image: NSImage
    let onClose: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Dark background
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            // Image with zoom and pan
            VStack {
                Spacer()
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 0.5), 5.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                // Reset if zoomed out too much
                                if scale < 1.0 {
                                    withAnimation(.spring(response: 0.3)) {
                                        scale = 1.0
                                        offset = .zero
                                    }
                                }
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                Spacer()
            }

            // Controls overlay
            VStack {
                HStack {
                    Spacer()

                    // Close button
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .help("Close (or click background)")
                    .padding()
                }

                Spacer()

                // Zoom controls
                HStack(spacing: 20) {
                    // Zoom out
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            scale = max(scale * 0.8, 0.5)
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Zoom out")

                    // Reset zoom
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    } label: {
                        Text("\(Int(scale * 100))%")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Reset zoom")

                    // Zoom in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            scale = min(scale * 1.25, 5.0)
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Zoom in")
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            // Enable keyboard shortcuts
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Escape key
                    onClose()
                    return nil
                }
                return event
            }
        }
    }
}
