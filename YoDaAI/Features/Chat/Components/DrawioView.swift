import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

// MARK: - DrawioView (plain-text mode fallback button)

struct DrawioView: View {
    let xmlContent: String

    var body: some View {
        Button(action: { openDiagramWindow(xmlContent: xmlContent) }) {
            HStack(spacing: 6) {
                Image(systemName: "flowchart")
                    .font(.system(size: 12, weight: .medium))
                Text("Open Diagram")
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

// MARK: - Open diagram in a real resizable NSWindow

func openDiagramWindow(xmlContent: String) {
    let controller = DrawioDiagramWindowController(xmlContent: xmlContent)
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    // Retain the controller until the window closes
    DrawioDiagramWindowController.retain(controller)
}

// MARK: - DrawioDiagramWindowController

final class DrawioDiagramWindowController: NSWindowController, NSWindowDelegate {
    /// Keep controllers alive until their window closes.
    private static var retainedControllers: [DrawioDiagramWindowController] = []

    static func retain(_ c: DrawioDiagramWindowController) {
        retainedControllers.append(c)
    }

    init(xmlContent: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Diagram"
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("DrawioDiagramWindow")
        window.minSize = NSSize(width: 560, height: 420)
        window.center()

        super.init(window: window)
        window.delegate = self

        let view = DrawioDiagramView(xmlContent: xmlContent, onClose: { [weak self] in
            self?.close()
        })
        window.contentView = NSHostingView(rootView: view)
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        DrawioDiagramWindowController.retainedControllers.removeAll { $0 === self }
    }
}

// MARK: - DrawioDiagramSheet (SwiftUI sheet — used from MarkdownTextView code blocks)

/// Presented as a SwiftUI .sheet from within a code block button.
struct DrawioDiagramSheet: View {
    let xmlContent: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DrawioDiagramView(xmlContent: xmlContent, onClose: { dismiss() })
            .frame(minWidth: 760, minHeight: 540)
    }
}

// MARK: - DrawioDiagramView (shared content)

struct DrawioDiagramView: View {
    let xmlContent: String
    var onClose: (() -> Void)? = nil

    @State private var isLoading = true
    @State private var webViewRef: WKWebView? = nil
    @State private var copyImageFeedback = false
    @State private var savePanel: NSSavePanel? = nil
    @State private var zoomLevel = 1.0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            diagramArea
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            // Title
            HStack(spacing: 8) {
                Image(systemName: "flowchart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Diagram")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.trailing, 16)

            Divider().frame(height: 20)

            // Zoom controls
            HStack(spacing: 1) {
                zoomButton(systemImage: "minus", help: "Zoom Out") {
                    webViewRef?.evaluateJavaScript("graph.zoomOut(); window.webkit.messageHandlers.zoom.postMessage(graph.view.scale);", completionHandler: nil)
                }
                zoomButton(systemImage: "arrow.up.left.and.arrow.down.right", help: "Reset Zoom") {
                    webViewRef?.evaluateJavaScript("graph.fit(); graph.center(true,true); window.webkit.messageHandlers.zoom.postMessage(graph.view.scale);", completionHandler: nil)
                }
                zoomButton(systemImage: "plus", help: "Zoom In") {
                    webViewRef?.evaluateJavaScript("graph.zoomIn(); window.webkit.messageHandlers.zoom.postMessage(graph.view.scale);", completionHandler: nil)
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

            // Copy XML
            toolbarActionButton(systemImage: "doc.on.doc", label: "Copy XML") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(stripXMLDeclaration(xmlContent), forType: .string)
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

            // Open in draw.io
            toolbarActionButton(systemImage: "arrow.up.right.square", label: "Open in draw.io") {
                openInDrawio()
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

    // MARK: - Diagram area

    private var diagramArea: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            DrawioWebView(xmlContent: xmlContent, isLoading: $isLoading, webViewRef: $webViewRef, zoomLevel: $zoomLevel)
            if isLoading {
                ZStack {
                    Color(nsColor: .windowBackgroundColor).opacity(0.92)
                    VStack(spacing: 14) {
                        ProgressView().scaleEffect(1.2)
                        Text("Rendering diagram…")
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

    private func openInDrawio() {
        let cleaned = stripXMLDeclaration(xmlContent)
        let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://app.diagrams.net/?src=about#xml=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyAsImage() {
        guard let webView = webViewRef else { return }
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.bounds.size)
        webView.takeSnapshot(with: config) { image, error in
            guard let image else { return }
            DispatchQueue.main.async {
                // Write as TIFF data — NSImage doesn't directly implement NSPasteboardWriting
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
        panel.title = "Save Diagram"
        panel.nameFieldStringValue = "diagram"
        panel.allowedContentTypes = [.png, .pdf]
        panel.canSelectHiddenExtension = true

        // Present as a sheet on the containing window, or as a free-floating panel
        let window = webView.window ?? NSApp.keyWindow
        if let window {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                let ext = url.pathExtension.lowercased()
                if ext == "pdf" {
                    savePDF(to: url, webView: webView)
                } else {
                    savePNG(to: url, webView: webView)
                }
            }
        } else {
            // Fallback: run modally if no window available
            let response = panel.runModal()
            guard response == .OK, let url = panel.url else { return }
            let ext = url.pathExtension.lowercased()
            if ext == "pdf" {
                savePDF(to: url, webView: webView)
            } else {
                savePNG(to: url, webView: webView)
            }
        }
    }

    private func savePNG(to url: URL, webView: WKWebView) {
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.bounds.size)
        webView.takeSnapshot(with: config) { image, error in
            guard let image else {
                print("[DrawioView] Snapshot error: \(error?.localizedDescription ?? "unknown")")
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
                    print("[DrawioView] PDF error: \(error)")
                }
            }
        }
    }
}

// MARK: - DrawioWebView (NSViewRepresentable)

private struct DrawioWebView: NSViewRepresentable {
    let xmlContent: String
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
        webView.loadHTMLString(buildHTML(for: xmlContent), baseURL: nil)

        DispatchQueue.main.async { webViewRef = webView }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private static let mxClientJS: String = {
        guard let url = Bundle.main.url(forResource: "mxClient.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            return "console.error('mxClient.min.js missing');"
        }
        return js
    }()

    private func buildHTML(for xml: String) -> String {
        let jsonXML: String
        if let data = try? JSONSerialization.data(withJSONObject: [xml]),
           let str = String(data: data, encoding: .utf8), str.count > 2 {
            jsonXML = String(str.dropFirst().dropLast())
        } else {
            let esc = xml
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            jsonXML = "\"\(esc)\""
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body {
              width: 100%; height: 100%;
              background-image: radial-gradient(circle, #d0d0d0 1px, transparent 1px);
              background-size: 20px 20px;
              background-color: #fafafa;
              overflow: hidden;
            }
            #graph { width: 100%; height: 100%; background: transparent; }
          </style>
        </head>
        <body>
          <div id="graph"></div>
          <script>
            window.onerror = function(msg, src, line) {
              window.webkit.messageHandlers.log.postMessage('JS_ERROR: ' + msg + ' @' + src + ':' + line);
            };
          </script>
          <script>\(DrawioWebView.mxClientJS)</script>
          <script>
            (function() {
              if (typeof mxGraph === 'undefined') {
                window.webkit.messageHandlers.log.postMessage('mxGraph undefined');
                return;
              }

              var xml = \(jsonXML);
              var container = document.getElementById('graph');

              window.graph = new mxGraph(container);
              window.graph.setEnabled(false);
              window.graph.setTooltips(true);
              window.graph.setCellsMovable(false);
              window.graph.setCellsResizable(false);
              window.graph.setCellsEditable(false);
              window.graph.setCellsSelectable(false);
              window.graph.setConnectable(false);
              window.graph.setBorder(32);
              window.graph.setHtmlLabels(true);

              mxEvent.addMouseWheelListener(function(evt, up) {
                if (up) { window.graph.zoomIn(); } else { window.graph.zoomOut(); }
                window.webkit.messageHandlers.zoom.postMessage(window.graph.view.scale);
                mxEvent.consume(evt);
              }, container);

              function modelNode(xmlStr) {
                var doc = mxUtils.parseXml(xmlStr);
                var root = doc.documentElement;
                if (root.nodeName === 'mxGraphModel') return root;
                var m = root.getElementsByTagName('mxGraphModel');
                if (m.length > 0) return m[0];
                return root;
              }

              var node = modelNode(xml);
              var codec = new mxCodec(node.ownerDocument);
              codec.decode(node, window.graph.getModel());

              setTimeout(function() {
                window.graph.fit();
                window.graph.center(true, true);
                window.webkit.messageHandlers.zoom.postMessage(window.graph.view.scale);
                window.webkit.messageHandlers.ready.postMessage('ok');
              }, 150);
            })();
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
            case "log":   print("[DrawioView] \(message.body)")
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
