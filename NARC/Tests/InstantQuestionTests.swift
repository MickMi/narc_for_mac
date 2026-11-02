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
        service: FixedInstantQuestionAnswering(), webSearchEnabled: false
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
        service: FixedInstantQuestionAnswering(), webSearchEnabled: false)
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
        service: FixedInstantQuestionAnswering(), webSearchEnabled: false)
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
            let controller = InstantQuestionController(credentials: manager, store: store, service: FixedInstantQuestionAnswering(), webSearchEnabled: false)
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
    await #expect(throws: InstantQuestionServiceFailure.interruptedResponse) {
        _ = try await service.streamAnswer(
            messages: [InstantQuestionMessage(role: .user, content: "question")],
            attachment: nil,
            credentials: InstantQuestionCredentials(deepSeekAPIKey: "secret"),
            onChunk: { _ in }
        )
    }
}

@Test(arguments: [false, true])
func deepSeekLengthLimitPreservesLastDeltaAndReportsTruncation(unterminated: Bool) async throws {
    let last = "data: {\"choices\":[{\"delta\":{\"content\":\"末段中文🎵\"},\"finish_reason\":\"length\"}]}"
    let sse = last + (unterminated ? "" : "\n\ndata: [DONE]\n\n")
    let transport = RecordingInstantQuestionTransport(responses: [(Data(sse.utf8), 200)])
    let collector = InstantQuestionChunkCollector()
    await #expect(throws: InstantQuestionServiceFailure.outputLimit) {
        _ = try await DeepSeekQuestionService(transport: transport).streamAnswer(
            messages: [InstantQuestionMessage(role: .user, content: "详细解释")], attachment: nil,
            credentials: InstantQuestionCredentials(deepSeekAPIKey: "fixture"),
            onChunk: { await collector.append($0) })
    }
    #expect(await collector.chunks == ["末段中文🎵"])
    let request = try #require(await transport.requests.first)
    let data = try #require(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    let body = try #require(object as? [String: Any])
    #expect(body["max_tokens"] as? Int == 8192)
    #expect(request.timeoutInterval == 120)
}

@Test func deepSeekLongStreamPreservesEveryChunkAndCompletion() async throws {
    let text = "长回答内容与 **Markdown**，🎵。\n"
    let delta = try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": text]]]])
    let sse = String(repeating: "data: " + String(decoding: delta, as: UTF8.self) + "\n\n", count: 1800)
        + "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
    let transport = RecordingInstantQuestionTransport(responses: [(Data(sse.utf8), 200)])
    let collector = InstantQuestionChunkCollector()
    let reply = try await DeepSeekQuestionService(transport: transport).streamAnswer(
        messages: [InstantQuestionMessage(role: .user, content: "长回答")], attachment: nil,
        credentials: InstantQuestionCredentials(deepSeekAPIKey: "fixture"),
        onChunk: { await collector.append($0) })
    #expect(reply.answer == String(repeating: text, count: 1800).trimmingCharacters(in: .whitespacesAndNewlines))
    #expect(await collector.chunks.count == 1800)
}

@Test func deepSeekParserBoundsEntireMultilineEvent() throws {
    var parser = DeepSeekEventStreamParser()
    _ = try parser.consume("data: " + String(repeating: "a", count: 150_000))
    #expect(throws: InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")) {
        _ = try parser.consume("data: " + String(repeating: "b", count: 150_000))
    }
}

/// Unlike the transport and static snapshot tests, keep the production window
/// alive while a tall answer grows and finishes.
/// Run this test with an external timeout: a layout loop also blocks MainActor timers.
@Test @MainActor func instantQuestionLiveLongAnswerKeepsWindowResponsive() async throws {
    _ = NSApplication.shared
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("fixture", for: InstantQuestionCredentialManager.deepSeekAccount)
    let (chunks, continuation) = AsyncThrowingStream<String, Error>.makeStream()
    defer { continuation.finish() }
    let controller = InstantQuestionController(
        credentials: await authorizedQuestionTestCredentials(secrets),
        store: InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json")),
        service: ManualStreamingInstantQuestionAnswering(chunks: chunks), webSearchEnabled: false)
    let window = InstantQuestionWindow(controller: controller, store: controller.store, onOpenPreferences: {})
    defer { window.close() }
    window.setContentSize(NSSize(width: 760, height: 620))
    window.present()
    let host = try #require(window.contentView)
    host.layoutSubtreeIfNeeded()
    controller.draft = "请详细解释，并列出具体步骤"
    controller.sendDraft()
    var expected = ""
    for index in 1...32 {
        let chunk = "\n\n## 第 \(index) 部分\n\n**核心结论**：先写清楚，再写简洁。\n- 依据和条件要明确，长回答需要能够持续阅读。\n- 保留当前内容，不阻塞输入与停止操作。\n> 这是一段引用，包含可以换行的中文说明。\n"
        expected += chunk
        continuation.yield(chunk)
        try await Task.sleep(for: .milliseconds(110))
        host.layoutSubtreeIfNeeded()
        // Resize halfway through, exercising wrapping and automatic tail scroll.
        if index == 16 { window.setContentSize(NSSize(width: 680, height: 520)) }
        if index % 8 == 0 {
            FileHandle.standardError.write(Data("long-answer heartbeat \(index)\n".utf8))
        }
    }
    try await Task.sleep(for: .milliseconds(350))
    #expect(controller.streamingAnswer == expected)
    #expect(controller.isBusy)
    if let path = ProcessInfo.processInfo.environment["NARC_INSTANT_QA_SNAPSHOT_DIR"], path.hasPrefix("/private/tmp/") {
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("live-long-answer.png"))
    }
    continuation.finish()
    for _ in 0..<100 where controller.isBusy { try await Task.sleep(for: .milliseconds(10)) }
    host.layoutSubtreeIfNeeded()
    #expect(controller.latestAnswer == expected)
    #expect(!controller.isBusy)
    #expect(controller.messages.count == 2)
    #expect(controller.store.records.isEmpty)
}

@Test(arguments: [680.0, 1040.0]) @MainActor
func instantQuestionMultipleLongRoundsKeepLayoutResponsive(width: Double) async throws {
    _ = NSApplication.shared
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("fixture", for: InstantQuestionCredentialManager.deepSeekAccount)
    let controller = InstantQuestionController(
        credentials: await authorizedQuestionTestCredentials(secrets),
        store: InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json")),
        service: PacedLongQuestionAnswering(), webSearchEnabled: false)
    let window = InstantQuestionWindow(controller: controller, store: controller.store, onOpenPreferences: {})
    defer { window.close() }
    window.setContentSize(NSSize(width: width, height: 620))
    window.present()
    let host = try #require(window.contentView)
    // Cross the API's recent-12-message context boundary while retaining all
    // displayed history. The window must not need closing between rounds.
    let roundCount = width == 680 ? 8 : 4
    for round in 1...roundCount {
        controller.draft = String(repeating: "第\(round)轮的问题比较长，需要完整解释，并且最后给出结论。", count: 8)
        controller.sendDraft()
        for _ in 0..<800 where controller.isBusy {
            try await Task.sleep(for: .milliseconds(10))
            host.layoutSubtreeIfNeeded()
        }
        #expect(!controller.isBusy)
        #expect(controller.errorMessage == nil)
        #expect(controller.messages.count == round * 2)
        #expect(controller.latestAnswer?.hasSuffix("本轮结束。") == true)
        // Exercise hide/show without clearing the in-memory conversation.
        window.orderOut(nil)
        window.present()
        host.layoutSubtreeIfNeeded()
        FileHandle.standardError.write(Data("long-answer width=\(width) round=\(round)\n".utf8))
    }
    #expect(controller.store.records.isEmpty)
    controller.clearCurrent()
    try await Task.sleep(for: .milliseconds(150))
    host.layoutSubtreeIfNeeded()
    #expect(controller.messages.isEmpty && controller.streamingAnswer.isEmpty)
}

@Test @MainActor func instantQuestionStopPreservesPartialAndContinuationContext() async throws {
    _ = NSApplication.shared
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("fixture", for: InstantQuestionCredentialManager.deepSeekAccount)
    let (chunks, continuation) = AsyncThrowingStream<String, Error>.makeStream()
    defer { continuation.finish() }
    let controller = InstantQuestionController(credentials: await authorizedQuestionTestCredentials(secrets),
        store: InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json")),
        service: ManualStreamingInstantQuestionAnswering(chunks: chunks), webSearchEnabled: false)
    controller.draft = "详细说明"
    controller.sendDraft()
    continuation.yield("已经回答的前半段")
    for _ in 0..<40 where controller.streamingAnswer.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    if let path = ProcessInfo.processInfo.environment["NARC_INSTANT_QA_SNAPSHOT_DIR"], path.hasPrefix("/private/tmp/") {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: InstantQuestionView(controller: controller,
            store: controller.store, onOpenPreferences: {}))
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("streaming-stop.png"))
        window.close()
    }
    controller.stopAnswer()
    #expect(!controller.isBusy)
    #expect(controller.streamingAnswer == "已经回答的前半段")
    #expect(controller.errorMessage?.contains("已停止") == true)
    #expect(controller.store.records.isEmpty)
    controller.draft = "请继续"
    controller.sendDraft()
    #expect(controller.messages.map(\.role) == [.user, .assistant, .user])
    #expect(controller.messages[1].content == "已经回答的前半段")
    #expect(controller.messages[2].content == "请继续")
    controller.clearCurrent()
    try await Task.sleep(for: .milliseconds(150))
    #expect(controller.messages.isEmpty && controller.streamingAnswer.isEmpty)
    #expect(controller.phase == .idle)
}

@Test @MainActor func instantQuestionLengthLimitContinuesWithPartialAnswerInRealRequest() async throws {
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("fixture", for: InstantQuestionCredentialManager.deepSeekAccount)
    let partial = "## 长回答\n\n" + String(repeating: "- **要点**：这里是已收到的内容。\n", count: 90)
    let event = try JSONSerialization.data(withJSONObject: ["choices": [[
        "delta": ["content": partial], "finish_reason": "length",
    ]]])
    let first = Data(("data: " + String(decoding: event, as: UTF8.self) + "\n\ndata: [DONE]\n\n").utf8)
    let second = Data("data: {\"choices\":[{\"delta\":{\"content\":\"接着上一段回答。\"}}]}\n\ndata: [DONE]\n\n".utf8)
    let transport = RecordingInstantQuestionTransport(responses: [(first, 200), (second, 200)])
    let controller = InstantQuestionController(credentials: await authorizedQuestionTestCredentials(secrets),
        store: InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json")),
        service: DeepSeekQuestionService(transport: transport), webSearchEnabled: false)
    controller.draft = "详细说明"
    controller.sendDraft()
    for _ in 0..<100 where controller.phase != .failed { try await Task.sleep(for: .milliseconds(10)) }
    #expect(controller.phase == .failed)
    #expect(controller.streamingAnswer == partial)
    #expect(controller.errorMessage == InstantQuestionServiceFailure.outputLimit.localizedDescription)
    #expect(!controller.canSave && !controller.isBusy)
    for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: InstantQuestionView(controller: controller,
            store: controller.store, onOpenPreferences: {}).environment(\.colorScheme, scheme))
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        if let path = ProcessInfo.processInfo.environment["NARC_INSTANT_QA_SNAPSHOT_DIR"], path.hasPrefix("/private/tmp/") {
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("long-answer-\(name).png"))
        }
        window.close()
    }
    controller.draft = "请继续"
    controller.sendDraft()
    for _ in 0..<100 where controller.isBusy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(controller.phase == .idle)
    #expect(controller.latestAnswer == "接着上一段回答。")
    #expect(controller.messages.map(\.role) == [.user, .assistant, .user, .assistant])
    let request = try #require(await transport.requests.last)
    let data = try #require(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    let body = try #require(object as? [String: Any])
    let messages = try #require(body["messages"] as? [[String: Any]])
    #expect(messages.count == 4) // System + first question + partial answer + continuation.
    #expect(messages[2]["content"] as? String == partial)
    #expect(messages[3]["content"] as? String == "请继续")
    #expect(controller.store.records.isEmpty)
    controller.clearCurrent()
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
        service: FixedInstantQuestionAnswering(), webSearchEnabled: false
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
        service: ManualStreamingInstantQuestionAnswering(chunks: chunks), webSearchEnabled: false
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
        service: ManualStreamingInstantQuestionAnswering(chunks: chunks), webSearchEnabled: false
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
        service: DeepSeekQuestionService(transport: transport), webSearchEnabled: false
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
        service: ManualStreamingInstantQuestionAnswering(chunks: chunks), webSearchEnabled: false
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
        service: FixedInstantQuestionAnswering(), webSearchEnabled: false
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
        service: TurnCountingInstantQuestionAnswering(), webSearchEnabled: false
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
    let suite = "narc-question-render-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = MemoryInstantQuestionSecretStore()
    try secrets.set("deepseek", for: InstantQuestionCredentialManager.deepSeekAccount)
    let credentials = InstantQuestionCredentialManager(secretStore: secrets)
    let store = InstantQuestionStore(storageURL: directory.appendingPathComponent("questions.json"))
    #expect(await credentials.authorizeRead())
    let controller = InstantQuestionController(
        credentials: credentials,
        store: store,
        service: FixedInstantQuestionAnswering(), webSearchEnabled: false, preferences: defaults
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
                initialMode: mode,
                onboardingDefaults: defaults
            )
            .environment(\.colorScheme, scheme)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
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
        #expect(view.bounds.width == 760)
        #expect(view.fittingSize.width <= 760)
        #expect(view.bounds.height == 620)
        #expect(view.fittingSize.height <= 620)
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
    let controller = InstantQuestionController(credentials: credentials, store: store, service: FixedInstantQuestionAnswering(), webSearchEnabled: false)
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
    window.orderOut(nil)
    window.present()
    try await Task.sleep(for: .milliseconds(150))
    let reopened = try #require(editor(in: host))
    #expect(window.isVisible)
    #expect(window.firstResponder === reopened)
    #expect(reopened.selectedRange().location == (controller.draft as NSString).length)
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
    let controller = InstantQuestionController(credentials: credentials, store: store, service: FixedInstantQuestionAnswering(), webSearchEnabled: false)
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
    private let streamedLines: AsyncThrowingStream<String, Error>?
    private(set) var requests: [URLRequest] = []

    init(responses: [(Data, Int)], streamedLines: AsyncThrowingStream<String, Error>? = nil) {
        self.responses = responses
        self.streamedLines = streamedLines
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
        if let streamedLines { return (streamedLines, response) }
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

private func nativeWebEvent(_ type: String, _ fields: [String: Any] = [:], trailingBlank: Bool = true) throws -> String {
    var value = fields
    value["type"] = type
    return "event: \(type)\ndata: " + String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        + (trailingBlank ? "\n\n" : "")
}

private func nativeWebResponse(_ answer: String, searched: Bool = true) -> [String: Any] {
    var output: [[String: Any]] = searched ? [["type": "web_search_call", "status": "completed"]] : []
    output.append(["type": "message", "role": "assistant", "content": [[
        "type": "output_text", "text": answer,
        "annotations": [["type": "url_citation", "url": "https://example.com/latest", "title": "官方赛程"]],
    ]]])
    return ["status": "completed", "output": output]
}

@Test(arguments: ["response.output_text.done", "response.content_part.done", "response.output_item.done"])
func nativeWebReadsDoneTextWhenTerminalOmitsIt(kind: String) async throws {
    let text = "搜索后的完整正文🎵"
    var fields: [String: Any] = ["output_index": 1, "content_index": 0]
    if kind == "response.output_text.done" { fields["text"] = text }
    if kind == "response.content_part.done" {
        fields["part"] = ["type": "output_text", "text": text,
            "annotations": [["type": "url_citation", "url": "https://example.com/done", "title": "来源"]]]
    }
    if kind == "response.output_item.done" {
        fields["item"] = ["type": "message", "content": [["type": "output_text", "text": text]]]
    }
    let sse = try nativeWebEvent("response.web_search_call.completed")
        + nativeWebEvent(kind, fields)
        + nativeWebEvent("response.completed", ["response": ["status": "completed"]])
    let transport = RecordingInstantQuestionTransport(responses: [(Data(sse.utf8), 200)])
    let chunks = InstantQuestionChunkCollector()
    let reply = try await DeepSeekQuestionService(transport: transport).streamAnswer(
        messages: [.init(role: .user, content: "最新赛程")], attachment: nil,
        credentials: .init(deepSeekAPIKey: "fixture"), webSearchEnabled: true,
        onSearch: {}, onChunk: { await chunks.append($0) })
    #expect(reply.answer == text)
    #expect(await chunks.chunks == [text])
    if kind == "response.content_part.done" { #expect(reply.sources.first?.url.absoluteString == "https://example.com/done") }
}

private func nativeSearchOnlyResponse() throws -> String {
    let search: [String: Any] = ["type": "web_search_call", "id": "search_fixture", "status": "completed",
        "action": ["type": "search", "query": "最新赛程", "sources": [["url": "https://example.com/schedule", "title": "赛程"]]],
        "search_results": [["title": "赛程", "url": "https://example.com/schedule", "content": "fixture search result"]]]
    return try nativeWebEvent("response.output_item.done", ["item": search])
        + nativeWebEvent("response.completed", ["response": ["status": "completed", "output": [search]]])
}

@Test func nativeWebContinuesSearchOnlyTurnOnce() async throws {
    let first = try nativeSearchOnlyResponse()
    let second = try nativeWebEvent("response.output_text.delta", ["delta": "根据刚才的搜索结果回答。"])
        + nativeWebEvent("response.completed", ["response": nativeWebResponse("根据刚才的搜索结果回答。", searched: false)])
    let transport = RecordingInstantQuestionTransport(responses: [(Data(first.utf8), 200), (Data(second.utf8), 200)])
    let reply = try await DeepSeekQuestionService(transport: transport).streamAnswer(
        messages: [.init(role: .user, content: "最新赛程")], attachment: nil,
        credentials: .init(deepSeekAPIKey: "fixture"), webSearchEnabled: true, onSearch: {}, onChunk: { _ in })
    #expect(reply.answer == "根据刚才的搜索结果回答。" && reply.webSearchUsed == true)
    let requests = await transport.requests
    #expect(requests.count == 2)
    let data = try #require(requests.last?.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    let body = try #require(object as? [String: Any])
    #expect(body["model"] as? String == "deepseek-v4-pro")
    #expect(body["tool_choice"] as? String == "none")
    let input = try #require(body["input"] as? [[String: Any]])
    #expect(input.last?["id"] as? String == "search_fixture")
    #expect(input.last?["search_results"] != nil)
    #expect(reply.sources.contains { $0.url.absoluteString == "https://example.com/schedule" })
}

@Test func nativeWebSearchOnlyContinuationIsBounded() async throws {
    let sse = try nativeSearchOnlyResponse()
    let transport = RecordingInstantQuestionTransport(responses: [(Data(sse.utf8), 200), (Data(sse.utf8), 200), (Data(sse.utf8), 200)])
    await #expect(throws: InstantQuestionServiceFailure.webSearchNoAnswer) {
        _ = try await DeepSeekQuestionService(transport: transport).streamAnswer(
            messages: [.init(role: .user, content: "最新赛程")], attachment: nil,
            credentials: .init(deepSeekAPIKey: "fixture"), webSearchEnabled: true, onSearch: {}, onChunk: { _ in })
    }
    #expect(await transport.requests.count == 2)
}

@Test func nativeWebReplayPreservesToolIdentityAndDiagnosticsExcludeContent() throws {
    var parser = DeepSeekResponsesStreamParser()
    let initial: [String: Any] = ["type": "web_search_call", "id": "tool_fixture", "status": "completed", "search_results": "private-result-marker"]
    let terminal: [String: Any] = ["type": "web_search_call", "id": "tool_fixture", "status": "completed", "extra": "updated"]
    let sse = try nativeWebEvent("response.output_item.done", ["item": initial])
        + nativeWebEvent("response.completed", ["response": ["status": "completed", "output": [terminal]]])
    for line in sse.components(separatedBy: "\n") { _ = try parser.consume(line) }
    #expect(parser.searchOutputs.count == 1)
    let raw = try #require(parser.searchOutputs.first)
    let decoded = try JSONSerialization.jsonObject(with: raw)
    let item = try #require(decoded as? [String: Any])
    #expect(item["search_results"] as? String == "private-result-marker")
    #expect(item["extra"] as? String == "updated")
    #expect(!parser.diagnosticSummary.contains("private-result-marker"))
    #expect(!parser.diagnosticSummary.contains("tool_fixture"))
    #expect(parser.diagnosticSummary.contains("search_items=1"))
}

@Test @MainActor func nativeWebSearchProgressStreamingStopAndModeCapture() async throws {
    let suite = "narc.web.stream.test." + UUID().uuidString
    let prefs = try #require(UserDefaults(suiteName: suite))
    defer { prefs.removePersistentDomain(forName: suite) }
    let credentials = InstantQuestionCredentialManager(secretStore: MemoryInstantQuestionSecretStore())
    #expect(credentials.saveDeepSeekKey("fixture"))
    let (lines, continuation) = AsyncThrowingStream<String, Error>.makeStream()
    defer { continuation.finish() }
    let transport = RecordingInstantQuestionTransport(responses: [(Data(), 200)], streamedLines: lines)
    let store = InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json"))
    let controller = InstantQuestionController(credentials: credentials, store: store,
        service: DeepSeekQuestionService(transport: transport), preferences: prefs)
    controller.draft = "查询最近赛程"
    controller.sendDraft()
    // The request captures its mode even if a later preference changes.
    controller.webSearchEnabled = false
    for line in try nativeWebEvent("response.web_search_call.searching").components(separatedBy: "\n") { continuation.yield(line) }
    for _ in 0..<100 where controller.phase != .searching { try await Task.sleep(for: .milliseconds(10)) }
    #expect(controller.phase == .searching && controller.isBusy)
    for line in try nativeWebEvent("response.output_text.delta", ["delta": "已查到的前半段"]).components(separatedBy: "\n") { continuation.yield(line) }
    for _ in 0..<100 where controller.streamingAnswer.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(controller.streamingAnswer == "已查到的前半段")
    #expect(controller.phase == .answering)
    controller.stopAnswer()
    for line in try nativeWebEvent("response.completed", ["response": nativeWebResponse("迟到回答")]).components(separatedBy: "\n") { continuation.yield(line) }
    continuation.finish()
    try await Task.sleep(for: .milliseconds(150))
    #expect(controller.phase == .failed && !controller.isBusy)
    #expect(controller.streamingAnswer == "已查到的前半段")
    #expect(controller.messages.count == 1 && !controller.canSave)
    #expect(store.records.isEmpty)
    let requests = await transport.requests
    #expect(requests.count == 1 && requests.first?.url?.path == "/responses")
}

@Test func nativeWebLongStreamPreservesAllVisibleChunks() async throws {
    let text = "中文🎵 **完整内容**\n"
    let delta = try nativeWebEvent("response.output_text.delta", ["delta": text])
    let answer = String(repeating: text, count: 400)
    let sse = try nativeWebEvent("response.web_search_call.completed")
        + String(repeating: delta, count: 400)
        + nativeWebEvent("response.completed", ["response": nativeWebResponse(answer)], trailingBlank: false)
    let transport = RecordingInstantQuestionTransport(responses: [(Data(sse.utf8), 200)])
    let chunks = InstantQuestionChunkCollector()
    let reply = try await DeepSeekQuestionService(transport: transport).streamAnswer(
        messages: [.init(role: .user, content: "长回答")], attachment: nil,
        credentials: .init(deepSeekAPIKey: "fixture"), webSearchEnabled: true,
        onSearch: {}, onChunk: { await chunks.append($0) })
    #expect(reply.answer == answer.trimmingCharacters(in: .whitespacesAndNewlines))
    #expect(await chunks.chunks.count == 400)
    #expect(reply.webSearchUsed == true)
}

@Test(arguments: [401, 429]) func nativeWebHTTPFailureDoesNotRetryOrFallBack(status: Int) async throws {
    let transport = RecordingInstantQuestionTransport(responses: [(Data(), status)])
    await #expect(throws: InstantQuestionServiceFailure.rejected(service: "DeepSeek", statusCode: status)) {
        _ = try await DeepSeekQuestionService(transport: transport).streamAnswer(
            messages: [.init(role: .user, content: "最近新闻")], attachment: nil,
            credentials: .init(deepSeekAPIKey: "fixture"), webSearchEnabled: true, onSearch: {}, onChunk: { _ in })
    }
    #expect(await transport.requests.count == 1)
}

@Test func nativeWebUsesProAutomaticSearchAndSameKey() async throws {
    let sse = try nativeWebEvent("response.web_search_call.searching")
        + nativeWebEvent("response.reasoning_text.delta", ["delta": "不应该展示的推理"])
        + nativeWebEvent("response.output_text.delta", ["delta": "**最新结果**"])
        + nativeWebEvent("response.completed", ["response": nativeWebResponse("**最新结果**。")])
    let transport = RecordingInstantQuestionTransport(responses: [(Data(sse.utf8), 200)])
    let chunks = InstantQuestionChunkCollector()
    let searches = InstantQuestionChunkCollector()
    let reply = try await DeepSeekQuestionService(transport: transport).streamAnswer(
        messages: (0..<16).map { InstantQuestionMessage(role: $0 % 2 == 0 ? .user : .assistant, content: "第\($0)条") },
        attachment: nil, credentials: .init(deepSeekAPIKey: "fixture-only"), webSearchEnabled: true,
        onSearch: { await searches.append("search") }, onChunk: { await chunks.append($0) })
    #expect(reply.answer == "**最新结果**。")
    #expect(await chunks.chunks == ["**最新结果**", "。"])
    #expect(await searches.chunks == ["search"])
    #expect(reply.webSearchUsed == true && reply.sources.count == 1)
    let requests = await transport.requests
    #expect(requests.count == 1)
    let request = try #require(requests.first)
    #expect(request.url?.absoluteString == "https://api.deepseek.com/responses")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only")
    let data = try #require(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    let body = try #require(object as? [String: Any])
    #expect(body["model"] as? String == "deepseek-v4-pro")
    #expect(body["tool_choice"] as? String == "auto")
    #expect((body["tools"] as? [[String: String]]) == [["type": "web_search"]])
    #expect((body["input"] as? [[String: String]])?.count == 12)
    #expect(body["stream"] as? Bool == true)
    #expect(body["max_output_tokens"] as? Int == 8192)
    #expect(body["previous_response_id"] == nil)
}

@Test(arguments: ["response.incomplete", "response.failed", "missing-terminal", "missing-search"])
func nativeWebFailureKeepsPartialWithoutOfflineFallback(kind: String) async throws {
    let partial = "已经收到的中文🎵"
    var sse = try nativeWebEvent("response.output_text.delta", ["delta": partial])
    let expected: InstantQuestionServiceFailure
    switch kind {
    case "response.incomplete":
        sse += try nativeWebEvent(kind, ["response": ["status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"]]], trailingBlank: false)
        expected = .outputLimit
    case "response.failed":
        sse += try nativeWebEvent(kind, ["response": ["status": "failed", "error": ["code": "tool_error", "message": "failed"]]])
        expected = .webSearchFailed
    case "missing-search":
        sse += try nativeWebEvent("response.completed", ["response": nativeWebResponse(partial, searched: false)])
        expected = .webSearchFailed
    default: expected = .interruptedResponse
    }
    let transport = RecordingInstantQuestionTransport(responses: [(Data(sse.utf8), 200)])
    let chunks = InstantQuestionChunkCollector()
    await #expect(throws: expected) {
        _ = try await DeepSeekQuestionService(transport: transport).streamAnswer(
            messages: [.init(role: .user, content: "最新消息")], attachment: nil,
            credentials: .init(deepSeekAPIKey: "fixture"), webSearchEnabled: true,
            onSearch: {}, onChunk: { await chunks.append($0) })
    }
    #expect(await chunks.chunks == [partial])
    #expect(await transport.requests.count == 1)
}

@Test func nativeWebRejectsImageBeforeAnyRequestAndBoundsEvents() async throws {
    let transport = RecordingInstantQuestionTransport(responses: [])
    await #expect(throws: InstantQuestionServiceFailure.webSearchWithImage) {
        _ = try await DeepSeekQuestionService(transport: transport).streamAnswer(
            messages: [.init(role: .user, content: "看图")],
            attachment: .init(name: "image.png", mediaType: "image/png", data: Data([1])),
            credentials: .init(deepSeekAPIKey: "fixture"), webSearchEnabled: true, onSearch: {}, onChunk: { _ in })
    }
    #expect(await transport.requests.isEmpty)
    var parser = DeepSeekResponsesStreamParser()
    _ = try parser.consume("data: " + String(repeating: "a", count: 150_000))
    #expect(throws: InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")) {
        _ = try parser.consume("data: " + String(repeating: "b", count: 150_000))
    }
}

@Test func nativeWebSourcesAreDeduplicatedSafeAndTextIsNotDuplicated() throws {
    var parser = DeepSeekResponsesStreamParser()
    let citations: [[String: Any]] = [
        ["type": "url_citation", "url": "https://example.com/a", "title": "A"],
        ["type": "url_citation", "url_citation": ["url": "https://example.com/a", "title": "重复"]],
        ["type": "url_citation", "url": "javascript:alert(1)"],
        ["type": "url_citation", "url": "https://secret@example.com"],
    ]
    let item: [String: Any] = ["type": "message", "content": [["type": "output_text", "text": "答案", "annotations": citations]]]
    let sse = try nativeWebEvent("response.output_text.delta", ["delta": "答案"])
        + nativeWebEvent("response.output_item.done", ["item": item])
        + nativeWebEvent("response.completed", ["response": ["status": "completed", "output": [item]]])
    var visible = ""
    for line in sse.components(separatedBy: "\n") { visible += try parser.consume(line)?.delta ?? "" }
    #expect(parser.sources.count == 1)
    #expect(parser.sources.first?.url.absoluteString == "https://example.com/a")
    #expect(visible == "答案" && parser.answer == "答案")
    #expect(!parser.webSearchUsed) // URLs in text are not proof of a search.
}

@Test @MainActor func nativeWebDefaultsOnRemembersChoiceAndImageSwitchIsExplicit() async throws {
    let suite = "narc.web.test." + UUID().uuidString
    let prefs = try #require(UserDefaults(suiteName: suite))
    defer { prefs.removePersistentDomain(forName: suite) }
    let secrets = MemoryInstantQuestionSecretStore()
    let credentials = InstantQuestionCredentialManager(secretStore: secrets)
    #expect(credentials.saveDeepSeekKey("fixture"))
    let offline = Data("data: {\"choices\":[{\"delta\":{\"content\":\"识图完成\"}}]}\n\ndata: [DONE]\n\n".utf8)
    let transport = RecordingInstantQuestionTransport(responses: [(offline, 200)])
    let store = InstantQuestionStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json"))
    let controller = InstantQuestionController(credentials: credentials, store: store,
        service: DeepSeekQuestionService(transport: transport), preferences: prefs)
    #expect(controller.webSearchEnabled)
    controller.draft = "解释图片"
    try controller.attachImage(name: "image.png", mediaType: "image/png", data: Data([1]))
    #expect(!controller.canSend)
    controller.sendDraft()
    #expect(controller.draft == "解释图片" && controller.imageAttachment != nil)
    #expect(controller.messages.isEmpty)
    #expect(await transport.requests.isEmpty)
    controller.useImageQuestionMode()
    #expect(!controller.webSearchEnabled && controller.canSend)
    controller.sendDraft()
    for _ in 0..<100 where controller.isBusy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(controller.latestAnswer == "识图完成" && controller.imageAttachment == nil)
    #expect(controller.messages.last?.webSearchUsed == nil)
    controller.clearCurrent()
    let recreated = InstantQuestionController(credentials: credentials, store: store, preferences: prefs)
    #expect(!recreated.webSearchEnabled)
    recreated.webSearchEnabled = true
    let again = InstantQuestionController(credentials: credentials, store: store, preferences: prefs)
    #expect(again.webSearchEnabled)
    #expect(store.records.isEmpty)
}

@Test @MainActor func nativeWebSavesSourcesAndRendersDefaultOnPreview() async throws {
    _ = NSApplication.shared
    let secrets = MemoryInstantQuestionSecretStore()
    let credentials = InstantQuestionCredentialManager(secretStore: secrets)
    #expect(credentials.saveDeepSeekKey("fixture"))
    let sse = try nativeWebEvent("response.web_search_call.searching")
        + nativeWebEvent("response.output_text.delta", ["delta": "## 最新赛程\n\n**已核实**：请以官方赛程的日期和时区为准。"])
        + nativeWebEvent("response.completed", ["response": nativeWebResponse("## 最新赛程\n\n**已核实**：请以官方赛程的日期和时区为准。")])
    let transport = RecordingInstantQuestionTransport(responses: [(Data(sse.utf8), 200)])
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("questions.json")
    let store = InstantQuestionStore(storageURL: file)
    let controller = InstantQuestionController(credentials: credentials, store: store,
        service: DeepSeekQuestionService(transport: transport), webSearchEnabled: true)
    controller.draft = "最近一场 NBA 比赛是什么时候？"
    controller.sendDraft()
    for _ in 0..<100 where controller.isBusy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(controller.messages.last?.webSearchUsed == true)
    #expect(controller.sources.count == 1)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(controller.saveCurrent())
    let reloaded = InstantQuestionStore(storageURL: file)
    #expect(reloaded.records.first?.messages.last?.webSearchUsed == true)
    #expect(reloaded.records.first?.sources.first?.url.absoluteString == "https://example.com/latest")
    // Legacy records omit the optional search metadata and continue to decode.
    let old = Data("{\"id\":\"D8348487-F7EB-4841-B207-BB86892A1BCB\",\"role\":\"assistant\",\"content\":\"旧回答\",\"createdAt\":0,\"sourceIDs\":[]}".utf8)
    #expect(try JSONDecoder().decode(InstantQuestionMessage.self, from: old).webSearchUsed == nil)
    for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
        for settings in [false, true] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: settings ? 630 : 680, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let content = settings ? AnyView(InstantQuestionSettingsView(controller: controller))
                : AnyView(InstantQuestionView(controller: controller, store: store, onOpenPreferences: {}))
            window.contentView = NSHostingView(rootView: content.environment(\.colorScheme, scheme))
            let host = try #require(window.contentView)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            if let path = ProcessInfo.processInfo.environment["NARC_INSTANT_QA_SNAPSHOT_DIR"], path.hasPrefix("/private/tmp/") {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("native-web-\(settings ? "settings" : "answer")-\(name).png"))
            }
            window.close()
        }
    }
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

private struct PacedLongQuestionAnswering: InstantQuestionAnswering {
    func answer(messages: [InstantQuestionMessage], attachment: InstantQuestionImageAttachment?,
                credentials: InstantQuestionCredentials) async throws -> InstantQuestionReply {
        throw InstantQuestionServiceFailure.invalidRequest
    }

    func streamAnswer(messages: [InstantQuestionMessage], attachment: InstantQuestionImageAttachment?,
                      credentials: InstantQuestionCredentials,
                      onChunk: @escaping @Sendable (String) async -> Void) async throws -> InstantQuestionReply {
        var answer = ""
        for index in 1...24 {
            try await Task.sleep(for: .milliseconds(95))
            let chunk = "\n\n## 步骤 \(index)\n\n**结论**：长回答要完整且可读。\n\n1. 先说明依据和边界，再给出可以操作的建议。\n- 中文、emoji 🎵、`代码` 和 **强调内容** 都需要正确换行。\n> 引用应保持内容高度稳定。\n\n```swift\nlet step = \(index)\n```\n"
            answer += chunk
            await onChunk(chunk)
        }
        answer += "\n本轮结束。"
        await onChunk("\n本轮结束。")
        return InstantQuestionReply(answer: answer, sources: [])
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
