import Foundation
import AppKit
import SwiftUI
import Testing
import LocalAuthentication
@testable import NARC

@Test @MainActor
func instantQuestionStorePersistsOnlyExplicitlySavedRecords() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let file = directory.appendingPathComponent("questions.json")
    let store = InstantQuestionStore(storageURL: file)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let record = SavedInstantQuestion(
        title: "今天有什么重要新闻？",
        messages: [
            InstantQuestionMessage(role: .user, content: "今天有什么重要新闻？", createdAt: now),
            InstantQuestionMessage(role: .assistant, content: "这里是联网后的回答 [1]。", createdAt: now),
        ],
        sources: [
            InstantQuestionSource(
                title: "示例来源",
                url: URL(string: "https://example.com/news")!,
                snippet: "摘要"
            ),
        ],
        createdAt: now
    )

    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(store.save(record))
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(InstantQuestionStore(storageURL: file).records == [record])
    #expect(store.delete(id: record.id))
    #expect(InstantQuestionStore(storageURL: file).records.isEmpty)
}

@Test @MainActor
func instantQuestionStoreDoesNotOverwriteUnreadableData() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("questions.json")
    let original = Data("not-json".utf8)
    try original.write(to: file)

    let store = InstantQuestionStore(storageURL: file)
    #expect(store.lastError == .loadFailed)
    #expect(!store.save(SavedInstantQuestion(title: "不会写入", messages: [], sources: [])))
    #expect(try Data(contentsOf: file) == original)
}

@Test @MainActor
func credentialManagerTrimsKeysAndReportsReadiness() throws {
    let secrets = MemoryInstantQuestionSecretStore()
    let manager = InstantQuestionCredentialManager(secretStore: secrets)
    #expect(!manager.isReady)

    #expect(manager.saveDeepSeekKey("  ds-key\n"))
    #expect(manager.isReady)
    #expect(try manager.credentials() == InstantQuestionCredentials(
        deepSeekAPIKey: "ds-key"
    ))

    #expect(manager.removeDeepSeekKey())
    #expect(!manager.isReady)
    #expect(throws: InstantQuestionCredentialFailure.missingDeepSeekKey) {
        _ = try manager.credentials()
    }
}

@Test @MainActor
func credentialStatusAvoidsSecretReadAndCachesExplicitSettingsAuthorization() async throws {
    let secrets = CountingInstantQuestionSecretStore()
    try secrets.set("first-key", for: InstantQuestionCredentialManager.deepSeekAccount)
    let manager = InstantQuestionCredentialManager(secretStore: secrets)
    #expect(manager.hasDeepSeekKey)
    #expect(!manager.isReady)
    #expect(secrets.statusReadCount == 1)
    #expect(secrets.secretReadCount == 0)

    manager.refreshStatus()
    #expect(secrets.secretReadCount == 0)
    #expect(throws: InstantQuestionCredentialFailure.authorizationRequired) { _ = try manager.credentials() }
    #expect(secrets.secretReadCount == 0)
    #expect(await manager.authorizeRead())
    #expect(manager.isReady)
    #expect(try manager.credentials().deepSeekAPIKey == "first-key")
    #expect(try manager.credentials().deepSeekAPIKey == "first-key")
    #expect(secrets.secretReadCount == 1)

    #expect(manager.saveDeepSeekKey(" second-key "))
    #expect(try manager.credentials().deepSeekAPIKey == "second-key")
    #expect(secrets.secretReadCount == 1)
    #expect(manager.removeDeepSeekKey())
    #expect(!manager.isReady)
    #expect(throws: InstantQuestionCredentialFailure.missingDeepSeekKey) {
        _ = try manager.credentials()
    }
}

@Test @MainActor
func instantQuestionSettingsRetriesAStartupKeychainFailureWhenShown() async throws {
    _ = NSApplication.shared
    let secrets = RecoveringInstantQuestionSecretStore()
    let credentials = InstantQuestionCredentialManager(secretStore: secrets)
    #expect(!credentials.isReady)
    #expect(credentials.lastError != nil)

    let storageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("questions.json")
    let controller = InstantQuestionController(
        credentials: credentials,
        store: InstantQuestionStore(storageURL: storageURL),
        service: FixedInstantQuestionAnswering()
    )
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: InstantQuestionSettingsView(controller: controller))
    defer { window.close() }

    window.contentView?.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(80))

    #expect(credentials.hasDeepSeekKey)
    #expect(!credentials.isReady) // Merely showing settings must not authorize a secret read.
    #expect(credentials.lastError == nil)
    #expect(secrets.readCount >= 2)
}

@Test func credentialPassiveStatusQueryCannotPresentAuthenticationUI() throws {
    let status = KeychainInstantQuestionSecretStore.readQuery(for: "fixture", secret: false)
    let context = try #require(status[kSecUseAuthenticationContext as String] as? LAContext)
    #expect(context.interactionNotAllowed)
    #expect(status[kSecReturnData as String] == nil)
    let explicit = KeychainInstantQuestionSecretStore.readQuery(for: "fixture", secret: true)
    #expect(explicit[kSecReturnData as String] as? Bool == true)
    #expect(explicit[kSecUseAuthenticationContext as String] == nil)
}

@Test @MainActor func credentialAuthorizationFailureKeepsDraftAndNeverRequestsAI() async throws {
    let secrets = CountingInstantQuestionSecretStore()
    try secrets.set("fixture-key", for: InstantQuestionCredentialManager.deepSeekAccount)
    secrets.secretReadError = InstantQuestionCredentialFailure.keychain(errSecUserCanceled)
    let manager = InstantQuestionCredentialManager(secretStore: secrets)
    let controller = InstantQuestionController(credentials: manager,
        store: InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json")),
        service: FixedInstantQuestionAnswering())
    controller.draft = "问题和图片都要保留"
    try controller.attachImage(name: "fixture.png", mediaType: "image/png", data: Data([1, 2]))
    controller.sendDraft()
    controller.validateConnection()
    #expect(secrets.secretReadCount == 0)
    #expect(controller.messages.isEmpty)
    #expect(controller.draft == "问题和图片都要保留")
    #expect(!controller.isCheckingConnection)
    #expect(!(await manager.authorizeRead()))
    #expect(secrets.secretReadCount == 1)
    #expect(!manager.isReady && !manager.isAuthorizing)
    #expect(manager.lastError != nil)
    #expect(controller.draft == "问题和图片都要保留")
    #expect(controller.imageAttachment?.name == "fixture.png")
    secrets.secretReadError = nil
    #expect(await manager.authorizeRead())
    #expect(manager.isReady)
    #expect(secrets.secretReadCount == 2)
    #expect(await manager.authorizeRead()) // Already ready is a no-op.
    #expect(secrets.secretReadCount == 2)
    controller.clearCurrent()
    #expect(manager.isReady) // Clearing the screen is not revoking cached credentials.
    let restarted = InstantQuestionCredentialManager(secretStore: secrets)
    #expect(restarted.hasDeepSeekKey && !restarted.isReady)
    #expect(secrets.secretReadCount == 2)
}

@Test @MainActor func instantQuestionSettingsRenderingDoesNotAuthorizeAndExplicitActionReadsOnce() async throws {
    _ = NSApplication.shared
    let secrets = CountingInstantQuestionSecretStore()
    try secrets.set("fixture-key", for: InstantQuestionCredentialManager.deepSeekAccount)
    let manager = InstantQuestionCredentialManager(secretStore: secrets)
    let controller = InstantQuestionController(credentials: manager,
        store: InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json")),
        service: FixedInstantQuestionAnswering())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 650),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: InstantQuestionSettingsView(controller: controller))
    defer { window.close() }
    let view = try #require(window.contentView)
    view.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(200))
    #expect(secrets.secretReadCount == 0)
    // CLI SwiftUI hosts do not publish their control AX tree. This checks the
    // explicit action and state only, not a native button-click acceptance.
    #expect(await manager.authorizeRead())
    #expect(manager.isReady && !manager.isAuthorizing)
    #expect(secrets.secretReadCount == 1)
    #expect(controller.connectionCheckMessage == nil)
    #expect(controller.messages.isEmpty)
}

@Test @MainActor func instantQuestionAuthorizationSettingsPreview() async throws {
    _ = NSApplication.shared
    for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
        for state in ["pending", "ready", "cancelled"] {
            let secrets = CountingInstantQuestionSecretStore()
            try secrets.set("fixture-only", for: InstantQuestionCredentialManager.deepSeekAccount)
            let manager = InstantQuestionCredentialManager(secretStore: secrets)
            if state == "ready" { #expect(await manager.authorizeRead()) }
            let store = InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json"))
            let controller = InstantQuestionController(credentials: manager, store: store, service: FixedInstantQuestionAnswering())
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 588, height: 520),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = NSHostingView(rootView: InstantQuestionSettingsView(controller: controller)
                .environment(\.colorScheme, scheme))
            let view = try #require(window.contentView)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            if state == "cancelled" {
                secrets.secretReadError = InstantQuestionCredentialFailure.keychain(errSecUserCanceled)
                #expect(!(await manager.authorizeRead()))
            }
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            if let path = ProcessInfo.processInfo.environment["NARC_INSTANT_QA_SNAPSHOT_DIR"], path.hasPrefix("/private/tmp/") {
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("authorization-\(state)-\(name).png"))
            }
            #expect(manager.isReady == (state == "ready"))
            #expect(!FileManager.default.fileExists(atPath: store.storageURL.path))
            window.close()
        }
    }
}

@Test
func deepSeekQuestionServiceSendsImageWithoutSearchRequest() async throws {
    let deepSeek = Data("""
    {"choices":[{"message":{"role":"assistant","content":"图片里是一张 NARC 截图。"}}]}
    """.utf8)
    let transport = RecordingInstantQuestionTransport(responses: [(deepSeek, 200)])
    let service = DeepSeekQuestionService(transport: transport)

    let reply = try await service.answer(
        messages: [InstantQuestionMessage(role: .user, content: "这张图片有什么问题？")],
        attachment: InstantQuestionImageAttachment(
            name: "screen.png",
            mediaType: "image/png",
            data: Data([1, 2, 3])
        ),
        credentials: InstantQuestionCredentials(deepSeekAPIKey: "secret-deepseek")
    )

    #expect(reply.answer == "图片里是一张 NARC 截图。")
    #expect(reply.sources.isEmpty)
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests[0].url?.host == "api.deepseek.com")
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer secret-deepseek")
    let body = String(data: try #require(requests[0].httpBody), encoding: .utf8) ?? ""
    #expect(body.contains("deepseek-flash"))
    #expect(body.contains("disabled"))
    #expect(body.contains("image_url"))
    #expect(body.contains("data:image\\/png;base64,AQID"))
    #expect(body.contains("没有实时网页搜索能力"))
    #expect(!body.contains("secret-deepseek"))
    #expect(!body.contains("api.search.brave.com"))
}

@Test
func deepSeekByteStreamPreservesEventBoundaries() async throws {
    let sse = "data: {\"choices\":[{\"delta\":{\"content\":\"你好 **NARC**\"}}]}\n\ndata: [DONE]\n\n"
    let bytes = AsyncStream<UInt8> { continuation in
        for byte in sse.utf8 { continuation.yield(byte) }
        continuation.finish()
    }
    var lines: [String] = []
    var events: [DeepSeekStreamEvent] = []
    var parser = DeepSeekEventStreamParser()
    for try await line in URLSessionInstantQuestionTransport.eventLines(from: bytes) {
        lines.append(line)
        if let event = try parser.consume(line) { events.append(event) }
    }
    #expect(lines.filter(\.isEmpty).count == 2)
    #expect(events == [.delta("你好 **NARC**"), .done])
    #expect(try parser.finish() == nil)
}

@Test(arguments: ["\n", "\r\n", "\r"])
func deepSeekByteStreamAcceptsSSELineEndingsAndUnterminatedDone(
    newline: String
) async throws {
    let sse = [
        ": keep-alive", "",
        "event: message",
        "data: {\"choices\":[",
        "data: {\"delta\":{\"content\":\"分段中文与 🎵\"}}]}", "",
        "data: [DONE]",
    ].joined(separator: newline)
    let bytes = AsyncStream<UInt8> { continuation in
        for byte in sse.utf8 { continuation.yield(byte) }
        continuation.finish()
    }
    var events: [DeepSeekStreamEvent] = []
    var parser = DeepSeekEventStreamParser()
    for try await line in URLSessionInstantQuestionTransport.eventLines(from: bytes) {
        if let event = try parser.consume(line) { events.append(event) }
    }
    if let event = try parser.finish() { events.append(event) }
    #expect(events == [.delta("分段中文与 🎵"), .done])
}

@Test(arguments: [false, true])
func deepSeekByteStreamRejectsOversizedOrInvalidUTF8Lines(invalidUTF8: Bool) async throws {
    let bytes: [UInt8] = invalidUTF8 ? [0xFF, 0x0A] : .init(repeating: 0x61, count: 262_145)
    let source = AsyncStream<UInt8> { continuation in
        for byte in bytes { continuation.yield(byte) }
        continuation.finish()
    }
    await #expect(throws: InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")) {
        for try await _ in URLSessionInstantQuestionTransport.eventLines(from: source) {}
    }
}

@Test(.timeLimit(.minutes(1)))
func deepSeekByteStreamDispatchesBeforeResponseEnds() async throws {
    let (bytes, continuation) = AsyncStream<UInt8>.makeStream()
    defer { continuation.finish() }
    var lines = URLSessionInstantQuestionTransport.eventLines(from: bytes).makeAsyncIterator()
    var parser = DeepSeekEventStreamParser()
    for byte in "data: {\"choices\":[{\"delta\":{\"content\":\"首段\"}}]}\n\n".utf8 {
        continuation.yield(byte)
    }
    let dataLine = try #require(try await lines.next())
    let separator = try #require(try await lines.next())
    #expect(try parser.consume(dataLine) == nil)
    #expect(try parser.consume(separator) == .delta("首段"))

    // Only send the completion marker after observing the first delta.
    for byte in "data: [DONE]\n\n".utf8 { continuation.yield(byte) }
    let doneLine = try #require(try await lines.next())
    let doneSeparator = try #require(try await lines.next())
    #expect(try parser.consume(doneLine) == nil)
    #expect(try parser.consume(doneSeparator) == .done)
    continuation.finish()
    #expect(try await lines.next() == nil)
}

@Test
func deepSeekStreamParserAcceptsDeltasAndRequiresDone() throws {
    var parser = DeepSeekEventStreamParser()
    #expect(try parser.consume(": keep-alive") == nil)
    #expect(try parser.consume("data: {\"choices\":[{\"delta\":{\"content\":\"**Afro\"}}]}") == nil)
    #expect(try parser.consume("") == .delta("**Afro"))
    #expect(try parser.consume("data: {\"choices\":[]}") == nil)
    #expect(try parser.consume("") == nil)
    #expect(try parser.consume("data: [DONE]") == nil)
    #expect(try parser.consume("") == .done)
    #expect(try parser.finish() == nil)
    #expect(throws: InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")) {
        _ = try parser.consume("data: not-json")
        _ = try parser.consume("")
    }
}

@Test
func deepSeekQuestionServiceStreamsMarkdownWithoutSearchRequest() async throws {
    let sse = [
        ": keep-alive",
        "",
        "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"**Afro\"}}]}",
        "",
        "data: {\"choices\":[{\"delta\":{\"content\":\" House** 是一种音乐。\"}}]}",
        "",
        "data: [DONE]",
        "",
    ].joined(separator: "\n")
    let transport = RecordingInstantQuestionTransport(responses: [(Data(sse.utf8), 200)])
    let service = DeepSeekQuestionService(transport: transport)
    let collector = InstantQuestionChunkCollector()

    let reply = try await service.streamAnswer(
        messages: [InstantQuestionMessage(role: .user, content: "什么是 Afro House？")],
        attachment: nil,
        credentials: InstantQuestionCredentials(deepSeekAPIKey: "secret-deepseek"),
        onChunk: { await collector.append($0) }
    )
    #expect(reply.answer == "**Afro House** 是一种音乐。")
    #expect(await collector.chunks == ["**Afro", " House** 是一种音乐。"])
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests[0].url?.host == "api.deepseek.com")
    #expect(requests[0].value(forHTTPHeaderField: "Accept") == "text/event-stream")
    let body = String(decoding: try #require(requests[0].httpBody), as: UTF8.self)
    #expect(body.contains("\"stream\":true"))
    #expect(!body.contains("api.search.brave.com"))
    #expect(!body.contains("secret-deepseek"))
}

@Test
func deepSeekStreamRejectsTruncatedAnswerWithoutDone() async throws {
    let sse = "data: {\"choices\":[{\"delta\":{\"content\":\"未完成\"}}]}\n\n"
    let service = DeepSeekQuestionService(
        transport: RecordingInstantQuestionTransport(responses: [(Data(sse.utf8), 200)])
    )
    await #expect(throws: InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")) {
        _ = try await service.streamAnswer(
            messages: [InstantQuestionMessage(role: .user, content: "question")],
            attachment: nil,
            credentials: InstantQuestionCredentials(deepSeekAPIKey: "secret"),
            onChunk: { _ in }
        )
    }
}

@Test
func instantQuestionMarkdownInterpretsAssistantFormatting() throws {
    let blocks = InstantQuestionMarkdown.blocks(
        "**Afro House** 是一种音乐。\n\n## 主要特征\n- **节奏**：保留 House 的四四拍。\n- **音色**：常用马林巴。"
    )
    #expect(blocks == [
        .paragraph("**Afro House** 是一种音乐。"),
        .heading(2, "主要特征"),
        .bullet("**节奏**：保留 House 的四四拍。"),
        .bullet("**音色**：常用马林巴。"),
    ])
    let rendered = InstantQuestionMarkdown.attributed(
        "**Afro House** 是一种音乐。\n\n- **节奏**：保留 House 的四四拍。"
    )
    let visible = String(rendered.characters)
    #expect(visible.contains("Afro House"))
    #expect(visible.contains("节奏"))
    #expect(!visible.contains("**"))
    #expect(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
}

@Test
func deepSeekRejectionIsReportedWithoutFallbackSearch() async throws {
    let transport = RecordingInstantQuestionTransport(responses: [(Data(), 401)])
    let service = DeepSeekQuestionService(transport: transport)

    await #expect(throws: InstantQuestionServiceFailure.rejected(
        service: "DeepSeek",
        statusCode: 401
    )) {
        _ = try await service.answer(
            messages: [InstantQuestionMessage(role: .user, content: "question")],
            attachment: nil,
            credentials: InstantQuestionCredentials(deepSeekAPIKey: "bad-deepseek")
        )
    }
    #expect(await transport.requests.count == 1)
}

@Test
func bingSearchRequestUsesDirectBingURL() throws {
    let url = try #require(WebSearchProvider.bing.url(for: "  macOS 悬浮窗  "))
    #expect(url.host == "www.bing.com")
    #expect(url.path == "/search")
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.queryItems?.first(where: { $0.name == "q" })?.value == "macOS 悬浮窗")
}

@Test
func instantSearchToolbarUsesModeSpecificActions() {
    #expect(InstantQuestionView.Mode.ask.showsSavedQuestions)
    #expect(InstantQuestionView.Mode.ask.toolbarActionTitle == "清空当前")
    #expect(!InstantQuestionView.Mode.bing.showsSavedQuestions)
    #expect(InstantQuestionView.Mode.bing.toolbarActionTitle == "刷新")
    #expect(InstantQuestionView.Mode.bing.toolbarActionSystemImage == "arrow.clockwise")
    #expect(InstantQuestionView.Mode.bing.toolbarActionHelp == "刷新当前 Bing 页面")
    #expect(!InstantQuestionView.Mode.google.showsSavedQuestions)
    #expect(InstantQuestionView.Mode.google.toolbarActionTitle == "刷新")
    #expect(InstantQuestionView.Mode.google.toolbarActionHelp == "刷新当前 Google 页面")
}

@Test @MainActor
func instantQuestionStaysEphemeralUntilSaveAndCloseClearsCurrentScreen() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let questionFile = directory.appendingPathComponent("questions.json")
    let assistantFile = directory.appendingPathComponent("assistant.json")
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("deepseek", for: InstantQuestionCredentialManager.deepSeekAccount)
    let credentials = InstantQuestionCredentialManager(secretStore: secrets)
    let questionStore = InstantQuestionStore(storageURL: questionFile)
    #expect(await credentials.authorizeRead())
    let controller = InstantQuestionController(
        credentials: credentials,
        store: questionStore,
        service: FixedInstantQuestionAnswering()
    )
    try controller.attachImage(
        name: "private-screen.png",
        mediaType: "image/png",
        data: Data([10, 20, 30])
    )
    controller.draft = "今天的产品新闻"
    controller.sendDraft()
    for _ in 0..<100 where controller.messages.count < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(controller.messages.count == 2)
    #expect(controller.messages.last?.sourceIDs.count == 1)
    #expect(!FileManager.default.fileExists(atPath: questionFile.path))
    #expect(controller.saveCurrent(now: Date(timeIntervalSince1970: 1_800_000_000)))
    #expect(FileManager.default.fileExists(atPath: questionFile.path))
    let savedData = try Data(contentsOf: questionFile)
    #expect(!String(decoding: savedData, as: UTF8.self).contains("private-screen.png"))

    _ = AssistantStore(storageURL: assistantFile)
    let window = InstantQuestionWindow(
        controller: controller,
        store: questionStore,
        onOpenPreferences: {}
    )
    #expect(window.selectedMode == .ask)
    window.selectMode(.bing)
    #expect(window.selectedMode == .bing)
    window.selectMode(.google)
    #expect(window.selectedMode == .google)
    #expect(controller.messages.count == 2)
    window.selectMode(.ask)
    #expect(window.selectedMode == .ask)
    window.close()
    #expect(controller.messages.isEmpty)
    #expect(controller.imageAttachment == nil)
    #expect(questionStore.records.count == 1)
}

@Test(arguments: [false, true]) @MainActor
func instantQuestionShowsStreamBeforeCompletionAndSavesOnlyFinalAnswer(
    replacesAttachment: Bool
) async throws {
    _ = NSApplication.shared
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("deepseek", for: InstantQuestionCredentialManager.deepSeekAccount)
    var continuation: AsyncThrowingStream<String, Error>.Continuation!
    let chunks = AsyncThrowingStream<String, Error> { continuation = $0 }
    let storageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("questions.json")
    let controller = InstantQuestionController(
        credentials: await authorizedQuestionTestCredentials(secrets),
        store: InstantQuestionStore(storageURL: storageURL),
        service: ManualStreamingInstantQuestionAnswering(chunks: chunks)
    )
    try controller.attachImage(name: "current-round.png", mediaType: "image/png", data: Data([1, 2, 3]))
    controller.draft = "什么是 Afro House？"
    controller.sendDraft()
    continuation.yield("**Afro")
    for _ in 0..<40 where controller.streamingAnswer.isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.streamingAnswer == "**Afro")
    #expect(controller.imageAttachment?.name == "current-round.png")
    #expect(controller.messages.count == 1)
    #expect(!controller.canSave)
    #expect(!FileManager.default.fileExists(atPath: storageURL.path))

    if replacesAttachment {
        try controller.attachImage(name: "next-round.png", mediaType: "image/png", data: Data([4, 5, 6]))
    }
    continuation.yield(" House** 是一种音乐。")
    continuation.finish()
    for _ in 0..<40 where controller.messages.count < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.messages.last?.content == "**Afro House** 是一种音乐。")
    #expect(controller.streamingAnswer.isEmpty)
    if replacesAttachment {
        #expect(controller.imageAttachment?.name == "next-round.png")
    } else {
        #expect(controller.imageAttachment == nil)
    }
    #expect(controller.canSave)
    #expect(!FileManager.default.fileExists(atPath: storageURL.path))
}

@Test @MainActor
func instantQuestionKeepsInterruptedStreamOutOfSavedAnswers() async throws {
    _ = NSApplication.shared
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("deepseek", for: InstantQuestionCredentialManager.deepSeekAccount)
    var continuation: AsyncThrowingStream<String, Error>.Continuation!
    let chunks = AsyncThrowingStream<String, Error> { continuation = $0 }
    let controller = InstantQuestionController(
        credentials: await authorizedQuestionTestCredentials(secrets),
        store: InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json")),
        service: ManualStreamingInstantQuestionAnswering(chunks: chunks)
    )
    try controller.attachImage(name: "retry.png", mediaType: "image/png", data: Data([1, 2, 3]))
    controller.draft = "测试中断"
    controller.sendDraft()
    continuation.yield("只收到半段")
    continuation.finish(throwing: URLError(.networkConnectionLost))
    for _ in 0..<40 where controller.phase != .failed {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.phase == .failed)
    #expect(controller.imageAttachment?.name == "retry.png")
    #expect(controller.streamingAnswer == "只收到半段")
    #expect(controller.messages.count == 1)
    #expect(!controller.canSave)
    controller.clearCurrent()
    #expect(controller.streamingAnswer.isEmpty)
}

@Test @MainActor
func instantQuestionSendsImageOnlyForItsOwnRound() async throws {
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("fixture-key", for: InstantQuestionCredentialManager.deepSeekAccount)
    let sse = Data("data: {\"choices\":[{\"delta\":{\"content\":\"回答完成\"}}]}\n\ndata: [DONE]\n\n".utf8)
    let transport = RecordingInstantQuestionTransport(responses: [(sse, 200), (sse, 200)])
    let storageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json")
    let controller = InstantQuestionController(
        credentials: await authorizedQuestionTestCredentials(secrets),
        store: InstantQuestionStore(storageURL: storageURL),
        service: DeepSeekQuestionService(transport: transport)
    )
    try controller.attachImage(name: "one-round.png", mediaType: "image/png", data: Data([1, 2, 3]))
    controller.draft = "解释这张图片"
    controller.sendDraft()
    for _ in 0..<100 where controller.isBusy {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.phase == .idle)
    #expect(controller.messages.count == 2)
    #expect(controller.imageAttachment == nil)

    controller.draft = "继续文字问答"
    controller.sendDraft()
    for _ in 0..<100 where controller.isBusy {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.phase == .idle)
    #expect(controller.messages.count == 4)
    let requests = await transport.requests
    #expect(requests.count == 2)
    let first = try #require(requests.first?.httpBody)
    let last = try #require(requests.last?.httpBody)
    #expect(String(decoding: first, as: UTF8.self).contains("image_url"))
    #expect(!String(decoding: last, as: UTF8.self).contains("image_url"))
    #expect(!String(decoding: last, as: UTF8.self).contains("base64"))
    #expect(!FileManager.default.fileExists(atPath: storageURL.path))
}

@Test @MainActor
func clearingQuestionIgnoresLateStreamChunks() async throws {
    _ = NSApplication.shared
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("deepseek", for: InstantQuestionCredentialManager.deepSeekAccount)
    var continuation: AsyncThrowingStream<String, Error>.Continuation!
    let chunks = AsyncThrowingStream<String, Error> { continuation = $0 }
    let controller = InstantQuestionController(
        credentials: await authorizedQuestionTestCredentials(secrets),
        store: InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json")),
        service: ManualStreamingInstantQuestionAnswering(chunks: chunks)
    )
    controller.draft = "将被清空的问题"
    controller.sendDraft()
    continuation.yield("已经开始")
    for _ in 0..<40 where controller.streamingAnswer.isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!controller.streamingAnswer.isEmpty)
    controller.clearCurrent()
    continuation.yield("不应出现")
    continuation.finish()
    try await Task.sleep(for: .milliseconds(80))
    #expect(controller.messages.isEmpty)
    #expect(controller.streamingAnswer.isEmpty)
    #expect(controller.phase == .idle)
}

@Test @MainActor
func clearingCurrentQuestionDoesNotDeleteSavedRecords() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("deepseek", for: InstantQuestionCredentialManager.deepSeekAccount)
    let store = InstantQuestionStore(storageURL: directory.appendingPathComponent("questions.json"))
    let controller = InstantQuestionController(
        credentials: await authorizedQuestionTestCredentials(secrets),
        store: store,
        service: FixedInstantQuestionAnswering()
    )
    controller.draft = "需要保留的问答"
    controller.sendDraft()
    for _ in 0..<100 where controller.messages.count < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.saveCurrent())

    controller.clearCurrent()

    #expect(controller.draft.isEmpty)
    #expect(controller.messages.isEmpty)
    #expect(controller.imageAttachment == nil)
    #expect(store.records.count == 1)
}

@Test @MainActor
func savingCurrentConversationIncludesEveryTurnAndLatestAnswerIsOneRound() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("deepseek", for: InstantQuestionCredentialManager.deepSeekAccount)
    let store = InstantQuestionStore(storageURL: directory.appendingPathComponent("questions.json"))
    let controller = InstantQuestionController(
        credentials: await authorizedQuestionTestCredentials(secrets),
        store: store,
        service: TurnCountingInstantQuestionAnswering()
    )

    controller.draft = "第一轮问题"
    controller.sendDraft()
    for _ in 0..<100 where controller.messages.count < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }
    controller.draft = "第二轮追问"
    controller.sendDraft()
    for _ in 0..<100 where controller.messages.count < 4 {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(controller.latestAnswer == "第 2 轮回答")
    #expect(controller.saveCurrent())
    #expect(store.records.count == 1)
    #expect(store.records[0].messages.map(\.content) == [
        "第一轮问题",
        "第 1 轮回答",
        "第二轮追问",
        "第 2 轮回答",
    ])
}

@Test @MainActor
func imagePasteboardInputAcceptsImagesAndLeavesTextForNormalPaste() throws {
    _ = NSApplication.shared
    let imagePasteboard = NSPasteboard.withUniqueName()
    defer { imagePasteboard.clearContents() }
    imagePasteboard.declareTypes([.png], owner: nil)
    imagePasteboard.setData(Data([1, 2, 3]), forType: .png)

    let pastedImage = try InstantQuestionImageInput.attachment(from: imagePasteboard)
    let attachment = try #require(pastedImage)
    #expect(attachment.name == "剪贴板图片.png")
    #expect(attachment.mediaType == "image/png")
    #expect(attachment.data == Data([1, 2, 3]))

    let textView = InstantQuestionPasteAwareTextView()
    var pastedAttachment: InstantQuestionImageAttachment?
    textView.imagePasteboard = { imagePasteboard }
    textView.onPasteImage = { pasteboard in
        pastedAttachment = try? InstantQuestionImageInput.attachment(from: pasteboard)
        return pastedAttachment != nil
    }
    let pasteItem = NSMenuItem(title: "Paste", action: #selector(InstantQuestionPasteAwareTextView.paste(_:)), keyEquivalent: "v")
    textView.isEditable = true
    #expect(InstantQuestionImageInput.canPasteImage(from: imagePasteboard))
    #expect(textView.validateMenuItem(pasteItem))
    textView.paste(nil) // Exercise the same action targeted by Edit > Paste and ⌘V.
    #expect(pastedAttachment == attachment)

    pastedAttachment = nil
    textView.isEditable = false
    #expect(!textView.validateMenuItem(pasteItem))
    #expect(pastedAttachment == nil)

    let textPasteboard = NSPasteboard.withUniqueName()
    defer { textPasteboard.clearContents() }
    textPasteboard.setString("普通文字仍由输入框粘贴", forType: .string)
    #expect(try InstantQuestionImageInput.attachment(from: textPasteboard) == nil)
    #expect(!InstantQuestionImageInput.canPasteImage(from: textPasteboard))
    #expect(!textView.pasteImageIfAvailable(from: textPasteboard))
}

@Test @MainActor
func instantQuestionProductionViewRendersInBothAppearances() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("deepseek", for: InstantQuestionCredentialManager.deepSeekAccount)
    let credentials = InstantQuestionCredentialManager(secretStore: secrets)
    let store = InstantQuestionStore(storageURL: directory.appendingPathComponent("questions.json"))
    #expect(await credentials.authorizeRead())
    let controller = InstantQuestionController(
        credentials: credentials,
        store: store,
        service: FixedInstantQuestionAnswering()
    )
    controller.draft = "NARC 最近有什么新进展？"
    controller.sendDraft()
    for _ in 0..<100 where controller.messages.count < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.messages.count == 2)

    var previewWindows: [NSWindow] = []
    for (modeName, mode) in [("ask", InstantQuestionView.Mode.ask), ("bing", .bing), ("google", .google)] {
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            let content = InstantQuestionView(
                controller: controller,
                store: store,
                onOpenPreferences: {},
                initialMode: mode
            )
            .environment(\.colorScheme, scheme)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 430),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: content)
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        #expect(view.bounds.width == 680)
        #expect(view.bounds.height == 430)
        if let path = ProcessInfo.processInfo.environment["NARC_INSTANT_QA_SNAPSHOT_DIR"],
           path.hasPrefix("/private/tmp/") {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path),
                withIntermediateDirectories: true
            )
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let prefix = modeName == "ask" ? "instant-question" : "instant-question-\(modeName)"
            try png.write(to: URL(fileURLWithPath: path)
                .appendingPathComponent("\(prefix)-\(name).png"))
        }
        previewWindows.append(window)
        }
    }
    previewWindows.forEach { $0.close() }
}

@MainActor private func authorizedQuestionTestCredentials(_ secrets: InstantQuestionSecretStore) async -> InstantQuestionCredentialManager {
    let manager = InstantQuestionCredentialManager(secretStore: secrets)
    #expect(await manager.authorizeRead())
    return manager
}

@Test @MainActor func instantQuestionWindowFocusesComposerOnEveryExplicitPresentation() async throws {
    _ = NSApplication.shared
    let credentials = InstantQuestionCredentialManager(secretStore: MemoryInstantQuestionSecretStore())
    let store = InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json"))
    let controller = InstantQuestionController(credentials: credentials, store: store, service: FixedInstantQuestionAnswering())
    let window = InstantQuestionWindow(controller: controller, store: store, onOpenPreferences: {})
    defer { window.close() }
    func editor(in view: NSView) -> InstantQuestionPasteAwareTextView? {
        if let editor = view as? InstantQuestionPasteAwareTextView { return editor }
        return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }
    window.present()
    try await Task.sleep(for: .milliseconds(250))
    let host = try #require(window.contentView)
    let first = try #require(editor(in: host))
    #expect(window.firstResponder === first)
    #expect(first.isEditable) // Preparing a draft does not read credentials.
    #expect(!controller.canSend)
    let scroll = try #require(first.enclosingScrollView)
    #expect(scroll.convert(scroll.bounds, to: host).minX <= NarcSpacing.xl + 1)
    #expect(scroll.bounds.width >= host.bounds.width - NarcSpacing.xl * 2 - 1)
    let other = NSTextView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    host.addSubview(other)
    #expect(window.makeFirstResponder(other))
    controller.draft = "保留输入，不因普通重绘抢焦点"
    try await Task.sleep(for: .milliseconds(80))
    #expect(window.firstResponder === other)
    window.present()
    try await Task.sleep(for: .milliseconds(100))
    #expect(window.firstResponder === first)
    #expect(first.selectedRange().location == (controller.draft as NSString).length)
    other.removeFromSuperview()
    window.selectMode(.bing)
    try await Task.sleep(for: .milliseconds(100))
    window.selectMode(.ask)
    try await Task.sleep(for: .milliseconds(200))
    let returned = try #require(editor(in: host))
    #expect(window.firstResponder === returned)
    #expect(controller.draft == "保留输入，不因普通重绘抢焦点")
    #expect(!credentials.isReady)
}

@MainActor private func composerFixturePNG() throws -> Data {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: 1600, pixelsHigh: 1000, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    NSColor(calibratedRed: 0.94, green: 0.97, blue: 1, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1600, height: 1000).fill()
    NSColor.systemBlue.setFill()
    NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 500, height: 800), xRadius: 40, yRadius: 40).fill()
    ("NARC 图片预览" as NSString).draw(at: NSPoint(x: 670, y: 580), withAttributes: [
        .font: NSFont.systemFont(ofSize: 58, weight: .semibold), .foregroundColor: NSColor.black])
    ("缩略图 → 点击展开" as NSString).draw(at: NSPoint(x: 670, y: 430), withAttributes: [
        .font: NSFont.systemFont(ofSize: 38), .foregroundColor: NSColor.darkGray])
    return try #require(bitmap.representation(using: .png, properties: [:]))
}

@Test @MainActor func instantQuestionImagePreviewIsBoundedAndDoesNotAlterOriginal() throws {
    let data = try composerFixturePNG()
    let thumbnail = try #require(InstantQuestionImagePresentation.image(data: data, maximumPixelSize: 120))
    let large = try #require(InstantQuestionImagePresentation.image(data: data, maximumPixelSize: 800))
    #expect(max(thumbnail.size.width, thumbnail.size.height) <= 120)
    #expect(max(large.size.width, large.size.height) <= 800)
    #expect(abs(large.size.width / large.size.height - 1.6) < 0.01)
    #expect(InstantQuestionImagePresentation.image(data: Data([1, 2]), maximumPixelSize: 120) == nil)
    #expect(InstantQuestionImagePresentation.image(data: data, maximumPixelSize: 0) == nil)
}

@Test @MainActor func instantQuestionComposerImagePreviewRendersInBothAppearances() async throws {
    _ = NSApplication.shared
    let credentials = InstantQuestionCredentialManager(secretStore: MemoryInstantQuestionSecretStore())
    #expect(credentials.saveDeepSeekKey("fixture-only"))
    let store = InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json"))
    let controller = InstantQuestionController(credentials: credentials, store: store, service: FixedInstantQuestionAnswering())
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.clearContents() }
    let imageData = try composerFixturePNG()
    pasteboard.setData(imageData, forType: .png)
    let pasted = try InstantQuestionImageInput.attachment(from: pasteboard)
    let attachment = try #require(pasted)
    try controller.attachImage(name: attachment.name, mediaType: attachment.mediaType, data: attachment.data)
    controller.draft = "帮我看一下这张图"
    for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
        for (kind, content, size) in [
            ("composer", AnyView(InstantQuestionView(controller: controller, store: store, onOpenPreferences: {})), NSSize(width: 680, height: 430)),
            ("image-preview", AnyView(InstantQuestionAttachmentPreview(attachment: attachment)), NSSize(width: 640, height: 480))
        ] {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = NSHostingView(rootView: content.environment(\.colorScheme, scheme))
            let view = try #require(window.contentView)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            if let path = ProcessInfo.processInfo.environment["NARC_INSTANT_QA_SNAPSHOT_DIR"], path.hasPrefix("/private/tmp/") {
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(
                    to: URL(fileURLWithPath: path).appendingPathComponent("\(kind)-\(name).png"))
            }
            window.close()
        }
    }
    #expect(controller.imageAttachment?.data == imageData)
    #expect(!FileManager.default.fileExists(atPath: store.storageURL.path))
    controller.removeImage()
    #expect(controller.imageAttachment == nil)
    #expect(controller.draft == "帮我看一下这张图")
}

// Test mutations occur before/after awaited reads, never concurrently.
private final class MemoryInstantQuestionSecretStore: InstantQuestionSecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]

    func containsValue(for account: String) throws -> Bool { values[account] != nil }
    func value(for account: String) throws -> String? { values[account] }
    func set(_ value: String, for account: String) throws { values[account] = value }
    func removeValue(for account: String) throws { values[account] = nil }
}

private final class CountingInstantQuestionSecretStore: InstantQuestionSecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private(set) var statusReadCount = 0
    private(set) var secretReadCount = 0
    var secretReadError: Error?

    func containsValue(for account: String) throws -> Bool {
        statusReadCount += 1
        return values[account] != nil
    }

    func value(for account: String) throws -> String? {
        secretReadCount += 1
        if let secretReadError { throw secretReadError }
        return values[account]
    }

    func set(_ value: String, for account: String) throws { values[account] = value }
    func removeValue(for account: String) throws { values[account] = nil }
}

private final class RecoveringInstantQuestionSecretStore: InstantQuestionSecretStore, @unchecked Sendable {
    private(set) var readCount = 0

    func containsValue(for account: String) throws -> Bool {
        readCount += 1
        if readCount == 1 {
            throw InstantQuestionCredentialFailure.keychain(errSecInteractionNotAllowed)
        }
        return true
    }

    func value(for account: String) throws -> String? { "deepseek" }

    func set(_ value: String, for account: String) throws {}
    func removeValue(for account: String) throws {}
}

private actor RecordingInstantQuestionTransport: InstantQuestionTransport {
    private var responses: [(Data, Int)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Data, Int)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let next = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.1,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (next.0, response)
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in data { continuation.yield(byte) }
            continuation.finish()
        }
        return (URLSessionInstantQuestionTransport.eventLines(from: bytes), response)
    }
}

private actor InstantQuestionChunkCollector {
    private(set) var chunks: [String] = []
    func append(_ chunk: String) { chunks.append(chunk) }
}

private struct FixedInstantQuestionAnswering: InstantQuestionAnswering {
    func answer(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        credentials: InstantQuestionCredentials
    ) async throws -> InstantQuestionReply {
        InstantQuestionReply(
            answer: "**Afro House** 把非洲打击乐与 House 的四四拍结构结合，强调律动与层次。\n\n**主要特征：**\n- **节奏**：底鼓之上叠加鼓、沙锤与复节奏。\n- **音色**：常用马林巴、卡林巴和人声采样。\n- **氛围**：偏沉浸、仪式感。\n\n如果想找歌或做制作参考，可以继续追问。",
            sources: [
                InstantQuestionSource(
                    title: "NARC 产品更新",
                    url: URL(string: "https://example.com/narc")!,
                    snippet: "用于原生视图回归的固定联网结果。"
                ),
            ]
        )
    }
}

private struct TurnCountingInstantQuestionAnswering: InstantQuestionAnswering {
    func answer(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        credentials: InstantQuestionCredentials
    ) async throws -> InstantQuestionReply {
        let turn = messages.filter { $0.role == .user }.count
        return InstantQuestionReply(answer: "第 \(turn) 轮回答", sources: [])
    }
}

private struct ManualStreamingInstantQuestionAnswering: InstantQuestionAnswering {
    let chunks: AsyncThrowingStream<String, Error>

    func answer(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        credentials: InstantQuestionCredentials
    ) async throws -> InstantQuestionReply {
        throw InstantQuestionServiceFailure.invalidRequest
    }

    func streamAnswer(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        credentials: InstantQuestionCredentials,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> InstantQuestionReply {
        var answer = ""
        for try await chunk in chunks {
            answer += chunk
            await onChunk(chunk)
        }
        return InstantQuestionReply(answer: answer, sources: [])
    }
}
