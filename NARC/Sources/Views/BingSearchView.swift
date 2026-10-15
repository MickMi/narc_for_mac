import SwiftUI
import WebKit

enum WebSearchProvider: String {
    case bing, google

    var title: String { self == .bing ? "Bing" : "Google" }
    var homeURL: URL {
        URL(string: self == .bing ? "https://www.bing.com/?setlang=zh-hans" : "https://www.google.com/?hl=zh-CN")!
    }

    func url(for query: String) -> URL? {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        var components = URLComponents(string: self == .bing ? "https://www.bing.com/search" : "https://www.google.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: normalized),
            self == .bing ? URLQueryItem(name: "setlang", value: "zh-hans") : URLQueryItem(name: "hl", value: "zh-CN"),
        ]
        return components?.url
    }
}

struct WebSearchView: View {
    let provider: WebSearchProvider
    let refreshToken: UUID

    @Binding var query: String
    @Binding var pageURL: URL
    @State private var browserOpenFailed = false

    var body: some View {
        VStack(spacing: NarcSpacing.sm) {
            HStack(spacing: NarcSpacing.sm) {
                TextField("搜索网页…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)

                Button(action: search) {
                    Label("搜索", systemImage: "magnifyingglass")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(NarcFocusPrimaryButtonStyle())
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: NarcSpacing.xs) {
                Image(systemName: "globe")
                Text("直接打开 \(provider.title)；结果链接用默认浏览器打开，不发送给 DeepSeek。关闭窗口后丢弃网页会话。")
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.narcCaption)
            .foregroundStyle(Color.narcTextMuted)

            if browserOpenFailed {
                Text("无法打开默认浏览器，请检查系统的默认浏览器设置后重试。")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcDanger)
            }

            EphemeralSearchWebView(url: pageURL, onOpenFailure: { browserOpenFailed = true })
                .id(refreshToken)
                .clipShape(RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous)
                        .stroke(Color.narcBorder, lineWidth: 1)
                )
        }
    }

    private func search() {
        guard let url = provider.url(for: query) else { return }
        browserOpenFailed = false
        pageURL = url
    }
}

struct EphemeralSearchWebView: NSViewRepresentable {
    let url: URL
    var onOpenFailure: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenFailure: onOpenFailure)
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView(url: url)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenFailure = onOpenFailure
        // Compare requested URLs, not redirects in the loaded page, so a
        // SwiftUI redraw does not restart a search or reset its scroll position.
        guard context.coordinator.lastRequestedURL != url else { return }
        context.coordinator.lastRequestedURL = url
        webView.load(URLRequest(url: url))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var lastRequestedURL: URL?
        var onOpenFailure: () -> Void
        private let openURL: (URL) -> Bool

        init(openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
             onOpenFailure: @escaping () -> Void = {}) {
            self.openURL = openURL
            self.onOpenFailure = onOpenFailure
        }

        func makeWebView(url: URL) -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.allowsMagnification = true
            webView.navigationDelegate = self
            webView.uiDelegate = self
            lastRequestedURL = url
            webView.load(URLRequest(url: url))
            return webView
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                openExternal(navigationAction.request.url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            openExternal(navigationAction.request.url)
            return nil
        }

        func openExternal(_ url: URL?) {
            guard let url, let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), url.host != nil else { return }
            if !openURL(url) { onOpenFailure() }
        }
    }
}
