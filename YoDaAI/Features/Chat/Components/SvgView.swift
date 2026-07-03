import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

// MARK: - SvgPreviewView (inline preview in message — avoids feeding large SVG to markdown parser)

struct SvgPreviewView: View {
    let svgContent: String
    let enableMarkdown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar matching code block style
            HStack(spacing: 8) {
                Text("SVG")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                // View SVG pill button
                Button {
                    openSvgWindow(svgContent: svgContent)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 11, weight: .medium))
                        Text("View SVG")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                // Copy SVG button
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(svgContent, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Copy SVG")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))

            // Show a truncated preview of the SVG source
            Text(svgContent.prefix(500) + (svgContent.count > 500 ? "\n…" : ""))
                .font(.system(size: 12).monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(8)
                .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - SvgView (plain-text mode fallback button)

struct SvgView: View {
    let svgContent: String

    var body: some View {
        Button(action: { openSvgWindow(svgContent: svgContent) }) {
            HStack(spacing: 6) {
                Image(systemName: "photo.artframe")
                    .font(.system(size: 12, weight: .medium))
                Text("View SVG")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Open SVG in a resizable NSWindow

func openSvgWindow(svgContent: String) {
    let controller = SvgWindowController(svgContent: svgContent)
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    SvgWindowController.retain(controller)
}

// MARK: - SvgWindowController

final class SvgWindowController: NSWindowController, NSWindowDelegate {
    private static var retainedControllers: [SvgWindowController] = []

    static func retain(_ c: SvgWindowController) {
        retainedControllers.append(c)
    }

    init(svgContent: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SVG Image"
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("SvgImageWindow")
        window.minSize = NSSize(width: 560, height: 420)
        window.center()

        super.init(window: window)
        window.delegate = self

        let view = SvgDiagramView(svgContent: svgContent, onClose: { [weak self] in
            self?.close()
        })
        window.contentView = NSHostingView(rootView: view)
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        SvgWindowController.retainedControllers.removeAll { $0 === self }
    }
}

// MARK: - SvgDiagramSheet (SwiftUI sheet)

struct SvgDiagramSheet: View {
    let svgContent: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SvgDiagramView(svgContent: svgContent, onClose: { dismiss() })
            .frame(minWidth: 760, minHeight: 540)
    }
}

// MARK: - SvgDiagramView (shared content)

struct SvgDiagramView: View {
    let svgContent: String
    var onClose: (() -> Void)? = nil

    @State private var isLoading = true
    @State private var webViewRef: WKWebView? = nil
    @State private var copyImageFeedback = false
    @State private var zoomLevel = 1.0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            svgArea
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            // Title
            HStack(spacing: 8) {
                Image(systemName: "photo.artframe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("SVG Image")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.trailing, 16)

            Divider().frame(height: 20)

            // Zoom controls
            HStack(spacing: 1) {
                zoomButton(systemImage: "minus", help: "Zoom Out") {
                    webViewRef?.evaluateJavaScript("zoomOut();", completionHandler: nil)
                }
                zoomButton(systemImage: "arrow.up.left.and.arrow.down.right", help: "Reset Zoom") {
                    webViewRef?.evaluateJavaScript("fit();", completionHandler: nil)
                }
                zoomButton(systemImage: "plus", help: "Zoom In") {
                    webViewRef?.evaluateJavaScript("zoomIn();", completionHandler: nil)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))

            Text("\(Int(zoomLevel * 100))%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
                .padding(.leading, 8)

            Spacer()

            // Copy SVG
            toolbarActionButton(systemImage: "doc.on.doc", label: "Copy SVG") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(svgContent, forType: .string)
            }

            Divider().frame(height: 20).padding(.horizontal, 8)

            // Copy as image
            toolbarActionButton(
                systemImage: copyImageFeedback ? "checkmark" : "photo.on.rectangle",
                label: copyImageFeedback ? "Copied!" : "Copy Image",
                tint: copyImageFeedback ? .green : nil
            ) {
                copyAsImage()
            }

            Divider().frame(height: 20).padding(.horizontal, 8)

            // Save as…
            toolbarActionButton(systemImage: "square.and.arrow.down", label: "Save As…") {
                saveAsImage()
            }

            Divider().frame(height: 20).padding(.horizontal, 8)

            // Close
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - SVG area

    private var svgArea: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            SvgWebView(svgContent: svgContent, isLoading: $isLoading, webViewRef: $webViewRef, zoomLevel: $zoomLevel)
            if isLoading {
                ZStack {
                    Color(nsColor: .windowBackgroundColor).opacity(0.92)
                    VStack(spacing: 14) {
                        ProgressView().scaleEffect(1.2)
                        Text("Rendering SVG…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isLoading)
    }

    // MARK: - Button helpers

    @ViewBuilder
    private func zoomButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private func toolbarActionButton(systemImage: String, label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 12))
            }
            .foregroundStyle(tint ?? Color.secondary)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Actions

    private func copyAsImage() {
        guard let webView = webViewRef else { return }
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.bounds.size)
        webView.takeSnapshot(with: config) { image, error in
            guard let image else { return }
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                if let tiff = image.tiffRepresentation {
                    NSPasteboard.general.setData(tiff, forType: .tiff)
                }
                withAnimation(.easeInOut(duration: 0.15)) { copyImageFeedback = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.2)) { copyImageFeedback = false }
                }
            }
        }
    }

    private func saveAsImage() {
        guard let webView = webViewRef else { return }

        let panel = NSSavePanel()
        panel.title = "Save SVG Image"
        panel.nameFieldStringValue = "image"
        panel.allowedContentTypes = [.png, .pdf, .svg]
        panel.canSelectHiddenExtension = true

        let window = webView.window ?? NSApp.keyWindow
        if let window {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                saveToURL(url, webView: webView)
            }
        } else {
            let response = panel.runModal()
            guard response == .OK, let url = panel.url else { return }
            saveToURL(url, webView: webView)
        }
    }

    private func saveToURL(_ url: URL, webView: WKWebView) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "svg":
            try? svgContent.data(using: .utf8)?.write(to: url)
        case "pdf":
            savePDF(to: url, webView: webView)
        default:
            savePNG(to: url, webView: webView)
        }
    }

    private func savePNG(to url: URL, webView: WKWebView) {
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.bounds.size)
        webView.takeSnapshot(with: config) { image, error in
            guard let image else {
                print("[SvgView] Snapshot error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            DispatchQueue.main.async {
                if let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: url)
                }
            }
        }
    }

    private func savePDF(to url: URL, webView: WKWebView) {
        let config = WKPDFConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.bounds.size)
        webView.createPDF(configuration: config) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    try? data.write(to: url)
                case .failure(let error):
                    print("[SvgView] PDF error: \(error)")
                }
            }
        }
    }
}

// MARK: - SvgWebView (NSViewRepresentable)

private struct SvgWebView: NSViewRepresentable {
    let svgContent: String
    @Binding var isLoading: Bool
    @Binding var webViewRef: WKWebView?
    @Binding var zoomLevel: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, zoomLevel: $zoomLevel)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "log")
        config.userContentController.add(context.coordinator, name: "ready")
        config.userContentController.add(context.coordinator, name: "zoom")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(buildHTML(for: svgContent), baseURL: nil)

        DispatchQueue.main.async { webViewRef = webView }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private func buildHTML(for svg: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body {
              width: 100%; height: 100%;
              overflow: hidden;
              background-image: radial-gradient(circle, #d0d0d0 1px, transparent 1px);
              background-size: 20px 20px;
              background-color: #fafafa;
              display: flex;
              align-items: center;
              justify-content: center;
            }
            #container {
              transform-origin: center;
              transition: transform 0.1s ease-out;
            }
            #container svg {
              max-width: 90vw;
              max-height: 90vh;
              display: block;
            }
          </style>
        </head>
        <body>
          <div id="container">\(svg)</div>
          <script>
            window.onerror = function(msg, src, line) {
              window.webkit.messageHandlers.log.postMessage('JS_ERROR: ' + msg + ' @' + src + ':' + line);
            };

            var scale = 1.0;
            var container = document.getElementById('container');

            function setZoom(s) {
              scale = s;
              container.style.transform = 'scale(' + scale + ')';
              window.webkit.messageHandlers.zoom.postMessage(scale);
            }
            function zoomIn() { setZoom(Math.min(scale * 1.2, 10)); }
            function zoomOut() { setZoom(Math.max(scale / 1.2, 0.1)); }
            function fit() {
              scale = 1.0;
              container.style.transform = '';
              window.webkit.messageHandlers.zoom.postMessage(1.0);
            }

            document.addEventListener('wheel', function(e) {
              e.preventDefault();
              if (e.deltaY < 0) { zoomIn(); } else { zoomOut(); }
            }, { passive: false });

            window.webkit.messageHandlers.ready.postMessage('ok');
          </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var isLoading: Bool
        @Binding var zoomLevel: Double

        init(isLoading: Binding<Bool>, zoomLevel: Binding<Double>) {
            _isLoading = isLoading
            _zoomLevel = zoomLevel
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "log":   print("[SvgView] \(message.body)")
            case "ready": DispatchQueue.main.async { self.isLoading = false }
            case "zoom":
                if let scale = message.body as? Double {
                    DispatchQueue.main.async { self.zoomLevel = scale }
                }
            default: break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.isLoading = false }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme ?? ""
            if scheme == "about" { decisionHandler(.allow); return }
            if (scheme == "https" || scheme == "http"), let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
