import SwiftUI
import WebKit
import AppKit

// MARK: - DrawioView

/// Shows a button to open the draw.io diagram in a full sheet viewer.
struct DrawioView: View {
    let xmlContent: String
    @State private var showSheet = false

    var body: some View {
        Button(action: { showSheet = true }) {
            Label("View Diagram", systemImage: "rectangle.on.rectangle")
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            DrawioDiagramSheet(xmlContent: xmlContent)
        }
    }
}

// MARK: - DrawioDiagramSheet

struct DrawioDiagramSheet: View {
    let xmlContent: String
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var webViewRef: WKWebView? = nil
    @State private var copyFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 4) {
                Text("Diagram")
                    .font(.headline)

                Spacer()

                // Zoom controls
                HStack(spacing: 2) {
                    toolbarButton(systemImage: "minus.magnifyingglass", help: "Zoom Out") {
                        webViewRef?.evaluateJavaScript("graph.zoomOut();", completionHandler: nil)
                    }
                    toolbarButton(systemImage: "arrow.up.left.and.arrow.down.right", help: "Fit to Window") {
                        webViewRef?.evaluateJavaScript("graph.fit(); graph.center(true, true);", completionHandler: nil)
                    }
                    toolbarButton(systemImage: "plus.magnifyingglass", help: "Zoom In") {
                        webViewRef?.evaluateJavaScript("graph.zoomIn();", completionHandler: nil)
                    }
                }
                .padding(.horizontal, 4)

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                // Copy as image
                toolbarButton(
                    systemImage: copyFeedback ? "checkmark" : "photo.on.rectangle",
                    help: "Copy as Image",
                    tint: copyFeedback ? .green : nil
                ) {
                    copyAsImage()
                }

                // Open in draw.io
                toolbarButton(systemImage: "arrow.up.right.square", help: "Open in draw.io") {
                    openInDrawio()
                }

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                // Close
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // WebView
            ZStack {
                DrawioWebView(xmlContent: xmlContent, isLoading: $isLoading, webViewRef: $webViewRef)
                if isLoading {
                    ProgressView("Rendering…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Actions

    private func openInDrawio() {
        let encoded = xmlContent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://app.diagrams.net/?src=about#xml=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyAsImage() {
        guard let webView = webViewRef else { return }
        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { image, error in
            guard let image else {
                print("[DrawioView] Snapshot error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                withAnimation(.easeInOut(duration: 0.15)) { copyFeedback = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.2)) { copyFeedback = false }
                }
            }
        }
    }

    // MARK: - Toolbar button helper

    @ViewBuilder
    private func toolbarButton(
        systemImage: String,
        help: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .foregroundStyle(tint ?? Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - DrawioWebView (NSViewRepresentable)

private struct DrawioWebView: NSViewRepresentable {
    let xmlContent: String
    @Binding var isLoading: Bool
    @Binding var webViewRef: WKWebView?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "log")
        config.userContentController.add(context.coordinator, name: "ready")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(buildHTML(for: xmlContent), baseURL: nil)

        // Expose the webView reference to the sheet toolbar
        DispatchQueue.main.async {
            webViewRef = webView
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    // MARK: - mxClient.min.js (loaded once from bundle)

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
            html, body { width: 100%; height: 100%; background: #ffffff; overflow: hidden; }
            #graph { width: 100%; height: 100%; }
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

              // Expose graph globally so toolbar buttons can call graph.zoomIn() etc.
              window.graph = new mxGraph(container);
              window.graph.setEnabled(false);
              window.graph.setTooltips(false);
              window.graph.setCellsMovable(false);
              window.graph.setCellsResizable(false);
              window.graph.setCellsEditable(false);
              window.graph.setCellsSelectable(false);
              window.graph.setConnectable(false);
              window.graph.setBorder(20);

              function modelNode(xmlStr) {
                var doc = mxUtils.parseXml(xmlStr);
                var root = doc.documentElement;
                if (root.nodeName === 'mxGraphModel') return root;
                var m = root.getElementsByTagName('mxGraphModel');
                if (m.length > 0) return m[0];
                return root;
              }

              var node = modelNode(xml);
              window.webkit.messageHandlers.log.postMessage('node: ' + node.nodeName + ' children: ' + node.childNodes.length);

              var codec = new mxCodec(node.ownerDocument);
              codec.decode(node, window.graph.getModel());

              setTimeout(function() {
                window.graph.fit();
                window.graph.center(true, true);
                var b = window.graph.getGraphBounds();
                window.webkit.messageHandlers.log.postMessage('bounds w=' + b.width + ' h=' + b.height);
                window.webkit.messageHandlers.ready.postMessage('ok');
              }, 200);
            })();
          </script>
        </body>
        </html>
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "log" {
                print("[DrawioView] \(message.body)")
            } else if message.name == "ready" {
                DispatchQueue.main.async { self.isLoading = false }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isLoading = false
            }
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
