import Foundation
import OSLog

/// Native server-side search: reuse the existing transport and the same Key.
/// The Responses stream has semantic terminal events, not Chat's [DONE].
struct DeepSeekWebQuestionService {
    let transport: InstantQuestionTransport
    private static let logger = Logger(subsystem: "com.mickmi.narc", category: "NativeWeb")

    func streamAnswer(
        messages: [InstantQuestionMessage], credentials: InstantQuestionCredentials,
        onSearch: @escaping @Sendable () async -> Void,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> InstantQuestionReply {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(credentials.deepSeekAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let payload = DeepSeekWebRequest(
            instructions: """
            你是 NARC 的轻量即时问答助手。今天是 \(formatter.string(from: Date()))。
            当前为联网模式：先使用网页搜索工具核实信息，再用用户所用语言回答。
            先给直接结论，再给必要解释；涉及最新比赛、新闻、价格等，注明事实日期。
            引用实际搜索到的来源并用 Markdown 链接提供网页。搜索失败或没有可靠来源时明确说明，不编造实时信息。
            对话中之前关于“没有联网能力”的回答不代表本轮工具能力。
            """,
            input: messages.suffix(12).map { .init(role: $0.role.rawValue, content: $0.content) })
        request.httpBody = try JSONEncoder().encode(payload)
        var searchWasUsed = false
        var allSources: [InstantQuestionSource] = []
        for generation in 0..<2 {
            try Task.checkCancellation()
            let parser = try await receive(request: request, onSearch: onSearch, onChunk: onChunk)
            // Only counts / fixed event categories: no prompt, response text,
            // URLs, credentials, or raw search items enter diagnostics.
            Self.logger.notice("native_web generation=\(generation, privacy: .public) \(parser.diagnosticSummary, privacy: .public)")
            if let failure = parser.failure { throw failure }
            guard parser.isFinished else { throw InstantQuestionServiceFailure.interruptedResponse }
            searchWasUsed = searchWasUsed || parser.webSearchUsed
            guard searchWasUsed else { throw InstantQuestionServiceFailure.webSearchFailed }
            for source in parser.sources where !allSources.contains(where: { $0.url == source.url }) {
                allSources.append(source)
            }
            let answer = parser.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !answer.isEmpty {
                return InstantQuestionReply(answer: answer, sources: allSources, webSearchUsed: true)
            }
            guard generation == 0, !parser.searchOutputs.isEmpty else {
                throw InstantQuestionServiceFailure.webSearchNoAnswer
            }
            // A completed native tool turn is not necessarily an assistant
            // message. Replay the provider's complete search items exactly once,
            // using the same Pro model and Key, then require text rather than
            // forcing the model to call the search tool again.
            let originalBody = try JSONSerialization.jsonObject(with: request.httpBody ?? Data())
            guard var body = originalBody as? [String: Any],
                  var input = body["input"] as? [[String: Any]] else {
                throw InstantQuestionServiceFailure.invalidRequest
            }
            for output in parser.searchOutputs {
                guard let item = try JSONSerialization.jsonObject(with: output) as? [String: Any] else {
                    throw InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")
                }
                input.append(item)
            }
            body["input"] = input
            body["tool_choice"] = "none"
            body["instructions"] = (body["instructions"] as? String ?? "")
                + "\n本轮检索已经完成，输入中的 web_search_call 是实际检索结果。请据此直接生成最终答案和来源链接，不再调用工具；结果不足时明确说明。"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        throw InstantQuestionServiceFailure.webSearchNoAnswer
    }

    private func receive(
        request: URLRequest, onSearch: @escaping @Sendable () async -> Void,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> DeepSeekResponsesStreamParser {
        let lines: AsyncThrowingStream<String, Error>
        let response: HTTPURLResponse
        do { (lines, response) = try await transport.lines(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw InstantQuestionServiceFailure.network }
        guard (200..<300).contains(response.statusCode) else {
            throw InstantQuestionServiceFailure.rejected(service: "DeepSeek", statusCode: response.statusCode)
        }
        var parser = DeepSeekResponsesStreamParser()
        func deliver(_ update: DeepSeekResponsesStreamParser.Update?) async {
            guard let update else { return }
            if update.searching { await onSearch() }
            if !update.delta.isEmpty { await onChunk(update.delta) }
        }
        do {
            for try await line in lines {
                try Task.checkCancellation()
                await deliver(try parser.consume(line))
                if parser.isFinished { break }
            }
            if !parser.isFinished { await deliver(try parser.finish()) }
        } catch is CancellationError { throw CancellationError() }
        catch let failure as InstantQuestionServiceFailure { throw failure }
        catch { throw InstantQuestionServiceFailure.network }
        return parser
    }
}

private struct DeepSeekWebRequest: Encodable {
    let model = "deepseek-v4-pro"
    let instructions: String
    let input: [Input]
    let stream = true
    let max_output_tokens = 8_192
    let reasoning = ["effort": "none"]
    let tools = [["type": "web_search"]]
    // Forcing a tool on every server-side step can exhaust the native search
    // loop without producing text. Let Pro finish after its search; actual
    // search completion is still checked before accepting an online answer.
    let tool_choice = "auto"

    struct Input: Encodable { let role: String; let content: String }
}

struct DeepSeekResponsesStreamParser {
    struct Update { var delta = ""; var searching = false }
    private var dataLines: [String] = []
    private var eventName = ""
    private var eventByteCount = 0
    private var answerByteCount = 0
    private var sourceURLs = Set<String>()
    private var completedTextParts: [Int: [Int: String]] = [:]
    private var replayByteCount = 0
    private var replayIndexByID: [String: Int] = [:]
    private var eventCount = 0
    private var deltaCount = 0
    private var doneTextCount = 0
    private var messageItemCount = 0
    private var terminalKind = "none"
    private(set) var searchOutputs: [Data] = []
    private(set) var answer = ""
    private(set) var sources: [InstantQuestionSource] = []
    private(set) var webSearchUsed = false
    private(set) var isFinished = false
    private(set) var failure: InstantQuestionServiceFailure?

    var diagnosticSummary: String {
        "events=\(eventCount) deltas=\(deltaCount) text_done=\(doneTextCount) message_items=\(messageItemCount) search_items=\(searchOutputs.count) search_used=\(webSearchUsed ? 1 : 0) answer_bytes=\(answerByteCount) terminal=\(terminalKind)"
    }

    mutating func consume(_ line: String) throws -> Update? {
        guard !isFinished else { return nil }
        if line.isEmpty { return try finish() }
        if line.hasPrefix("event:") {
            guard line.utf8.count < 160 else { throw invalidResponse }
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.first == " " { value.removeFirst() }
            eventByteCount += value.utf8.count
            guard eventByteCount <= 262_144 else { throw invalidResponse }
            dataLines.append(value)
        }
        return nil
    }

    mutating func finish() throws -> Update? {
        guard !dataLines.isEmpty else { eventName = ""; return nil }
        let data = Data(dataLines.joined(separator: "\n").utf8)
        let sseType = eventName
        dataLines.removeAll(keepingCapacity: true)
        eventName = ""
        eventByteCount = 0
        guard let event = try? JSONDecoder().decode(DeepSeekResponsesEvent.self, from: data),
              let type = event.type ?? (sseType.isEmpty ? nil : sseType) else { throw invalidResponse }
        var update = Update()
        eventCount += 1
        switch type {
        case "response.output_text.delta":
            deltaCount += 1
            guard let delta = event.delta else { throw invalidResponse }
            try append(delta)
            update.delta = delta
        case "response.web_search_call.in_progress", "response.web_search_call.searching":
            update.searching = true
        case "response.web_search_call.completed":
            webSearchUsed = true
        case "response.output_text.done":
            if let text = event.text {
                try rememberText(text, output: event.output_index ?? 0, part: event.content_index ?? 0)
            }
        case "response.content_part.done":
            if let part = event.part, part.type == "output_text", let text = part.text {
                try rememberText(text, output: event.output_index ?? 0, part: event.content_index ?? 0)
                for annotation in part.annotations ?? [] { collect(annotation) }
            }
        case "response.output_item.added", "response.output_item.done":
            if let item = event.item { collect(item) }
            if type == "response.output_item.done" {
                if let item = event.item, item.type == "message" {
                    messageItemCount += 1
                    for (index, part) in (item.content ?? []).enumerated() where part.type == "output_text" {
                        if let text = part.text { try rememberText(text, output: event.output_index ?? 0, part: index) }
                    }
                }
                try captureSearchOutputs(data, fromTerminal: false)
            }
        case "response.output_text.annotation.added":
            if let annotation = event.annotation { collect(annotation) }
        case "response.completed", "response.incomplete", "response.failed":
            guard let response = event.response else { throw invalidResponse }
            terminalKind = type == "response.completed" ? "completed" : (type == "response.incomplete" ? "incomplete" : "failed")
            try captureSearchOutputs(data, fromTerminal: true)
            for item in response.output ?? [] { collect(item) }
            var fullText = (response.output ?? []).filter { $0.type == "message" }
                .flatMap { $0.content ?? [] }.filter { $0.type == "output_text" }
                .compactMap(\.text).joined(separator: "\n")
            if fullText.isEmpty {
                fullText = completedTextParts.keys.sorted().flatMap { output in
                    (completedTextParts[output] ?? [:]).sorted { $0.key < $1.key }.map(\.value)
                }.joined(separator: "\n")
            }
            guard fullText.utf8.count <= 1_000_000 else { throw invalidResponse }
            if fullText.hasPrefix(answer) {
                let remainder = String(fullText.dropFirst(answer.count))
                try append(remainder)
                update.delta = remainder
            }
            isFinished = true
            if type == "response.incomplete" || response.status == "incomplete" {
                failure = response.incomplete_details?.reason == "max_output_tokens"
                    ? .outputLimit : .interruptedResponse
            } else if type == "response.failed" || response.status == "failed" || response.error != nil {
                failure = .webSearchFailed
            }
        case "error":
            isFinished = true
            failure = .webSearchFailed
        default:
            // Reasoning, tool arguments, and metadata are never answer text.
            break
        }
        return update
    }

    private var invalidResponse: InstantQuestionServiceFailure { .invalidResponse(service: "DeepSeek") }

    private mutating func rememberText(_ text: String, output: Int, part: Int) throws {
        guard completedTextParts.count < 100 || completedTextParts[output] != nil,
              (completedTextParts[output]?.count ?? 0) < 100 || completedTextParts[output]?[part] != nil,
              text.utf8.count <= 1_000_000 else { throw invalidResponse }
        completedTextParts[output, default: [:]][part] = text
        doneTextCount += 1
        let totalBytes = completedTextParts.values.reduce(0) { total, parts in
            total + parts.values.reduce(0) { $0 + $1.utf8.count }
        }
        guard totalBytes <= 1_000_000 else { throw invalidResponse }
    }

    private mutating func captureSearchOutputs(_ data: Data, fromTerminal: Bool) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw invalidResponse }
        let items: [[String: Any]]
        if fromTerminal {
            items = (object["response"] as? [String: Any])?["output"] as? [[String: Any]] ?? []
        } else {
            items = (object["item"] as? [String: Any]).map { [$0] } ?? []
        }
        for item in items where item["type"] as? String == "web_search_call" {
            let status = item["status"] as? String
            guard status == nil || status == "completed" else { continue }
            let id = item["id"] as? String
            if let id, let index = replayIndexByID[id] {
                // A terminal snapshot can add fields to the earlier done item.
                // Preserve opaque search data, replay each tool ID only once.
                var merged = try JSONSerialization.jsonObject(with: searchOutputs[index]) as? [String: Any] ?? [:]
                item.forEach { merged[$0.key] = $0.value }
                let raw = try JSONSerialization.data(withJSONObject: merged, options: .sortedKeys)
                replayByteCount += raw.count - searchOutputs[index].count
                guard replayByteCount <= 1_000_000 else { throw invalidResponse }
                searchOutputs[index] = raw
                continue
            }
            let raw = try JSONSerialization.data(withJSONObject: item, options: .sortedKeys)
            guard !searchOutputs.contains(raw) else { continue }
            replayByteCount += raw.count
            guard searchOutputs.count < 8, replayByteCount <= 1_000_000 else { throw invalidResponse }
            if let id { replayIndexByID[id] = searchOutputs.count }
            searchOutputs.append(raw)
        }
    }

    private mutating func append(_ text: String) throws {
        answerByteCount += text.utf8.count
        guard answerByteCount <= 1_000_000 else { throw invalidResponse }
        answer += text
    }

    private mutating func collect(_ item: DeepSeekResponsesItem) {
        if item.type == "web_search_call", item.status == "completed" { webSearchUsed = true }
        if item.type == "message" {
            for part in item.content ?? [] where part.type == "output_text" {
                for annotation in part.annotations ?? [] { collect(annotation) }
            }
        }
        if item.type == "web_search_call" {
            for source in item.action?.sources ?? [] { collect(source) }
        }
    }

    private mutating func collect(_ citation: DeepSeekResponsesCitation) {
        guard citation.type == nil || citation.type == "url_citation" else { return }
        let rawURL = citation.url_citation?.url ?? citation.url
        let title = citation.url_citation?.title ?? citation.title
        guard sources.count < 100, let raw = rawURL,
              raw.utf8.count <= 8192, let url = URL(string: raw),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil,
              sourceURLs.insert(url.absoluteString).inserted else { return }
        sources.append(InstantQuestionSource(title: String((title ?? url.host ?? "来源").prefix(300)),
                                             url: url, snippet: ""))
    }
}

private struct DeepSeekResponsesEvent: Decodable {
    let type: String?
    let delta: String?
    let item: DeepSeekResponsesItem?
    let annotation: DeepSeekResponsesCitation?
    let response: DeepSeekResponsesResponse?
    let text: String?
    let part: DeepSeekResponsesItem.Part?
    let output_index: Int?
    let content_index: Int?
}

private struct DeepSeekResponsesResponse: Decodable {
    let status: String?
    let output: [DeepSeekResponsesItem]?
    let incomplete_details: Incomplete?
    let error: ProviderError?
    struct Incomplete: Decodable { let reason: String? }
    struct ProviderError: Decodable { let code: String?; let message: String? }
}

private struct DeepSeekResponsesItem: Decodable {
    let type: String
    let status: String?
    let content: [Part]?
    let action: Action?
    struct Part: Decodable {
        let type: String
        let text: String?
        let annotations: [DeepSeekResponsesCitation]?
    }
    struct Action: Decodable { let sources: [DeepSeekResponsesCitation]? }
}

// Some compatible providers nest the URL citation; accept both encodings.
private struct DeepSeekResponsesCitation: Decodable {
    let type: String?
    let url: String?
    let title: String?
    let url_citation: URLCitation?
    struct URLCitation: Decodable { let url: String?; let title: String? }
}
