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

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Diagram")
                    .font(.headline)
                Spacer()
                Button(action: openInDrawio) {
                    Label("Open in draw.io", systemImage: "arrow.up.right.square")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // WebView
            ZStack {
                DrawioWebView(xmlContent: xmlContent, isLoading: $isLoading)
                if isLoading {
                    ProgressView("Rendering…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private func openInDrawio() {
        let encoded = xmlContent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://app.diagrams.net/?src=about#xml=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - DrawioWebView (NSViewRepresentable)

private struct DrawioWebView: NSViewRepresentable {
    let xmlContent: String
    @Binding var isLoading: Bool

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

              var graph = new mxGraph(container);
              graph.setEnabled(false);
              graph.setTooltips(false);
              graph.setCellsMovable(false);
              graph.setCellsResizable(false);
              graph.setCellsEditable(false);
              graph.setCellsSelectable(false);
              graph.setConnectable(false);
              graph.setBorder(20);

              // Resolve mxGraphModel node
              function modelNode(xmlStr) {
                var doc = mxUtils.parseXml(xmlStr);
                var root = doc.documentElement;
                if (root.nodeName === 'mxGraphModel') return root;
                // <mxfile> wrapper
                var m = root.getElementsByTagName('mxGraphModel');
                if (m.length > 0) return m[0];
                return root;
              }

              var node = modelNode(xml);
              window.webkit.messageHandlers.log.postMessage('node: ' + node.nodeName + ' children: ' + node.childNodes.length);

              var codec = new mxCodec(node.ownerDocument);
              codec.decode(node, graph.getModel());

              // Fit after layout
              setTimeout(function() {
                graph.fit();
                graph.center(true, true);
                var b = graph.getGraphBounds();
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
            // Fallback: hide spinner after 2s even if ready message didn't fire
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
