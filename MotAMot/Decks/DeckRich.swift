import SwiftUI
import WebKit

// MARK: - Rich content
// The web apps draw their visuals as HTML + SVG + CSS (code blocks, Excel grids,
// fretboards, staves, maps, animated slide demos). Rather than redraw each one,
// a small web view shows that snippet using the course's own stylesheet. It sizes
// itself to the content, so it sits inside a card like any other view.

struct DeckRich: View {
    let html: String
    let css: String
    var theme: String = ""
    @State private var height: CGFloat = 20

    var body: some View {
        DeckWebView(html: html, css: css, theme: theme, height: $height)
            .frame(height: max(height, 1))
    }
}

private let deckOverrideCSS = """
:root{padding:0!important}
html,body{background:none!important;background-image:none!important;margin:0!important;padding:0!important;height:auto!important;min-height:0!important}
#deck-root{padding:2px 0}
.pyrun .row,.pyout{display:none!important}
"""

private let deckHeightScript = """
(function(){
  var r = document.getElementById('deck-root');
  function post(){ window.webkit.messageHandlers.deckHeight.postMessage(Math.ceil(r.getBoundingClientRect().height)); }
  if (window.ResizeObserver) { new ResizeObserver(post).observe(r); }
  window.addEventListener('load', post);
  post();
})();
"""

struct DeckWebView: UIViewRepresentable {
    let html: String
    let css: String
    let theme: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "deckHeight")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let document = """
        <!doctype html><html data-theme="\(theme)"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style><style>\(deckOverrideCSS)</style></head>
        <body><div id="deck-root">\(html)</div><script>\(deckHeightScript)</script></body></html>
        """
        if context.coordinator.lastDocument != document {
            context.coordinator.lastDocument = document
            view.loadHTMLString(document, baseURL: nil)
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "deckHeight")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var lastDocument = ""

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = (message.body as? NSNumber)?.doubleValue else { return }
            DispatchQueue.main.async {
                let next = CGFloat(value)
                if abs(self.height.wrappedValue - next) > 0.5 { self.height.wrappedValue = next }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
