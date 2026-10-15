import AppKit
import Testing
import WebKit
@testable import NARC

@Test
func googleSearchUsesEncodedDirectURLWithoutAPI() throws {
    let query = "中文 & music + #1"
    let url = try #require(WebSearchProvider.google.url(for: "  \(query)\n"))
    #expect(url.host == "www.google.com")
    #expect(url.path == "/search")
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.queryItems?.first(where: { $0.name == "q" })?.value == query)
    #expect(WebSearchProvider.google.url(for: " \n") == nil)
    #expect(WebSearchProvider.google.homeURL.host == "www.google.com")
}

@Test @MainActor
func webSearchExternalOpenRejectsUnsafeSchemesAndReportsBrowserFailure() {
    var opened: [URL] = []
    var failures = 0
    let coordinator = EphemeralSearchWebView.Coordinator(openURL: {
        opened.append($0)
        return false
    }, onOpenFailure: { failures += 1 })
    for value in ["file:///private/tmp/example", "javascript:alert(1)", "narc://action", "about:blank"] {
        coordinator.openExternal(URL(string: value))
    }
    coordinator.openExternal(nil)
    #expect(opened.isEmpty)
    #expect(failures == 0)
    let target = URL(string: "https://example.com/article")!
    coordinator.openExternal(target)
    #expect(opened == [target])
    #expect(failures == 1)
}

// Exercise real WebKit navigation events rather than only a URL-policy helper.
// The injected opener records the request without launching a user's browser.
@Test(arguments: ["normal", "blank"])
@MainActor
func webSearchRealWebViewLinksOpenExternallyOnce(linkID: String) async throws {
    _ = NSApplication.shared
    var opened: [URL] = []
    let coordinator = EphemeralSearchWebView.Coordinator(openURL: {
        opened.append($0)
        return true
    })
    let view = coordinator.makeWebView(url: URL(string: "about:blank")!)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    defer {
        EphemeralSearchWebView.dismantleNSView(view, coordinator: coordinator)
        window.close()
    }
    #expect(!view.configuration.websiteDataStore.isPersistent)
    #expect(view.navigationDelegate === coordinator)
    #expect(view.uiDelegate === coordinator)
    view.stopLoading()
    view.loadHTMLString("""
    <html><body>
    <a id="normal" href="https://example.com/article">普通结果</a>
    <a id="blank" href="https://www.bing.com/ck/a?fixture=1" target="_blank">新窗口结果</a>
    </body></html>
    """, baseURL: nil)
    var ready = false
    for _ in 0..<100 {
        if (try? await view.evaluateJavaScript("document.getElementById('\(linkID)') !== null")) as? Bool == true {
            ready = true
            break
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    try #require(ready)
    #expect(opened.isEmpty) // Initial page loading stays embedded.
    _ = try await view.evaluateJavaScript("document.getElementById('\(linkID)').click()")
    for _ in 0..<100 where opened.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
    let expected = linkID == "normal" ? "https://example.com/article" : "https://www.bing.com/ck/a?fixture=1"
    #expect(opened.map(\.absoluteString) == [expected])
    #expect(view.url?.host != "example.com")
}
