import Foundation

enum InstantQuestionServiceFailure: LocalizedError, Equatable {
    case invalidRequest
    case network
    case rejected(service: String, statusCode: Int)
    case invalidResponse(service: String)
    case emptyAnswer

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "无法创建联网请求。"
        case .network:
            return "网络连接失败，请检查网络后重试。"
        case .rejected(let service, let statusCode):
            if statusCode == 401 || statusCode == 403 {
                return "\(service) 拒绝了密钥，请到偏好设置检查。"
            }
            if statusCode == 429 {
                return "\(service) 请求过于频繁或额度不足，请稍后重试。"
            }
            return "\(service) 暂时不可用（\(statusCode)）。"
        case .invalidResponse(let service):
            return "\(service) 返回了无法识别的结果。"
        case .emptyAnswer:
            return "DeepSeek 没有返回可显示的答案，请重试。"
        }
    }
}

protocol InstantQuestionTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse)
}

struct URLSessionInstantQuestionTransport: InstantQuestionTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw InstantQuestionServiceFailure.network
        }
        return (data, response)
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let (bytes, rawResponse) = try await URLSession.shared.bytes(for: request)
        guard let response = rawResponse as? HTTPURLResponse else {
            throw InstantQuestionServiceFailure.network
        }
        return (Self.eventLines(from: bytes), response)
    }

    static func eventLines<Bytes: AsyncSequence>(
        from bytes: Bytes
    ) -> AsyncThrowingStream<String, Error> where Bytes.Element == UInt8 {
        AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    var lineBytes: [UInt8] = []
                    var previousWasCarriageReturn = false
                    // AsyncLineSequence skips empty lines, but SSE uses them
                    // to dispatch events. Decode only after a full UTF-8 line.
                    func decodeLine() throws -> String {
                        guard let line = String(bytes: lineBytes, encoding: .utf8) else {
                            throw InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")
                        }
                        return line
                    }
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if byte == 0x0A, previousWasCarriageReturn {
                            previousWasCarriageReturn = false
                            continue
                        }
                        previousWasCarriageReturn = byte == 0x0D
                        if byte == 0x0A || byte == 0x0D {
                            continuation.yield(try decodeLine())
                            lineBytes.removeAll(keepingCapacity: true)
                        } else {
                            guard lineBytes.count < 262_144 else {
                                throw InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")
                            }
                            lineBytes.append(byte)
                        }
                    }
                    try Task.checkCancellation()
                    if !lineBytes.isEmpty { continuation.yield(try decodeLine()) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

protocol InstantQuestionAnswering {
    func answer(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        credentials: InstantQuestionCredentials
    ) async throws -> InstantQuestionReply

    func streamAnswer(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        credentials: InstantQuestionCredentials,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> InstantQuestionReply
}

extension InstantQuestionAnswering {
    func streamAnswer(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        credentials: InstantQuestionCredentials,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> InstantQuestionReply {
        let reply = try await answer(messages: messages, attachment: attachment, credentials: credentials)
        await onChunk(reply.answer)
        return reply
    }
}

struct DeepSeekQuestionService: InstantQuestionAnswering {
    private let transport: InstantQuestionTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(transport: InstantQuestionTransport = URLSessionInstantQuestionTransport()) {
        self.transport = transport
    }

    func answer(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        credentials: InstantQuestionCredentials
    ) async throws -> InstantQuestionReply {
        let answer = try await complete(
            messages: messages,
            attachment: attachment,
            apiKey: credentials.deepSeekAPIKey
        )
        return InstantQuestionReply(answer: answer, sources: [])
    }

    func streamAnswer(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        credentials: InstantQuestionCredentials,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> InstantQuestionReply {
        let request = try makeRequest(
            messages: messages,
            attachment: attachment,
            apiKey: credentials.deepSeekAPIKey,
            stream: true
        )
        let (lines, response): (AsyncThrowingStream<String, Error>, HTTPURLResponse)
        do {
            (lines, response) = try await transport.lines(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw InstantQuestionServiceFailure.network
        }
        guard (200..<300).contains(response.statusCode) else {
            throw InstantQuestionServiceFailure.rejected(service: "DeepSeek", statusCode: response.statusCode)
        }

        var parser = DeepSeekEventStreamParser()
        var answer = ""
        var answerByteCount = 0
        var finished = false
        do {
            for try await line in lines {
                try Task.checkCancellation()
                guard let event = try parser.consume(line) else { continue }
                switch event {
                case .delta(let content):
                    answerByteCount += content.utf8.count
                    guard answerByteCount <= 1_000_000 else {
                        throw InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")
                    }
                    answer += content
                    await onChunk(content)
                case .done:
                    finished = true
                }
                if finished { break }
            }
            if !finished, case .done? = try parser.finish() { finished = true }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as InstantQuestionServiceFailure {
            throw error
        } catch {
            throw InstantQuestionServiceFailure.network
        }
        guard finished else { throw InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek") }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InstantQuestionServiceFailure.emptyAnswer }
        return InstantQuestionReply(answer: trimmed, sources: [])
    }

    private func complete(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        apiKey: String
    ) async throws -> String {
        let request = try makeRequest(messages: messages, attachment: attachment, apiKey: apiKey, stream: false)
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw InstantQuestionServiceFailure.rejected(
                service: "DeepSeek",
                statusCode: response.statusCode
            )
        }
        guard let payload = try? decoder.decode(DeepSeekResponse.self, from: data),
              let rawAnswer = payload.choices.first?.message.content else {
            throw InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")
        }
        let answer = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw InstantQuestionServiceFailure.emptyAnswer }
        return answer
    }

    private func makeRequest(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        apiKey: String,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            throw InstantQuestionServiceFailure.invalidRequest
        }
        let system = """
        你是 NARC 的轻量即时问答助手。回答使用用户所用语言，先给直接结论，再给必要解释。
        如果用户提供图片，请直接分析图片；无法确认的细节要明确说明，不要编造。
        你没有实时网页搜索能力，不要声称已经联网、检索过网页或引用不存在的来源。
        """
        let recentMessages = Array(messages.suffix(12))
        var history = recentMessages.map {
            DeepSeekRequestMessage(role: $0.role.rawValue, content: .text($0.content))
        }
        if let attachment,
           let index = history.lastIndex(where: { $0.role == InstantQuestionRole.user.rawValue }) {
            history[index] = DeepSeekRequestMessage(
                role: InstantQuestionRole.user.rawValue,
                content: .multimodal(text: recentMessages[index].content, attachment: attachment)
            )
        }
        let payload = DeepSeekRequest(
            model: "deepseek-flash",
            messages: [DeepSeekRequestMessage(role: "system", content: .text(system))] + history,
            thinking: DeepSeekThinking(type: "disabled"),
            maxTokens: 2_000,
            stream: stream
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.httpBody = try encoder.encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if stream { request.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.data(for: request)
        } catch let error as InstantQuestionServiceFailure {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw InstantQuestionServiceFailure.network
        }
    }
}

private struct DeepSeekRequest: Encodable {
    let model: String
    let messages: [DeepSeekRequestMessage]
    let thinking: DeepSeekThinking
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, thinking, stream
        case maxTokens = "max_tokens"
    }
}

private struct DeepSeekThinking: Encodable {
    let type: String
}

private struct DeepSeekRequestMessage: Encodable {
    let role: String
    let content: DeepSeekRequestContent
}

private enum DeepSeekRequestContent: Encodable {
    case text(String)
    case multimodal(text: String, attachment: InstantQuestionImageAttachment)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .multimodal(let text, let attachment):
            try container.encode([
                DeepSeekContentPart.text(text),
                DeepSeekContentPart.image(attachment),
            ])
        }
    }
}

private enum DeepSeekContentPart: Encodable {
    case text(String)
    case image(InstantQuestionImageAttachment)

    private enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let attachment):
            try container.encode("image_url", forKey: .type)
            try container.encode(
                DeepSeekImageURL(
                    url: "data:\(attachment.mediaType);base64,\(attachment.data.base64EncodedString())",
                    detail: "auto"
                ),
                forKey: .imageURL
            )
        }
    }
}

private struct DeepSeekImageURL: Encodable {
    let url: String
    let detail: String
}

private struct DeepSeekResponseMessage: Decodable {
    let role: String
    let content: String
}

private struct DeepSeekResponse: Decodable {
    let choices: [DeepSeekChoice]
}

enum DeepSeekStreamEvent: Equatable {
    case delta(String)
    case done
}

struct DeepSeekEventStreamParser {
    private var dataLines: [String] = []
    private let decoder = JSONDecoder()

    mutating func consume(_ line: String) throws -> DeepSeekStreamEvent? {
        if line.isEmpty { return try finish() }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.first == " " { value.removeFirst() }
            guard value.utf8.count <= 262_144 else {
                throw InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")
            }
            dataLines.append(value)
        }
        // SSE comments and other fields (event:, id:, retry:) are not answer text.
        return nil
    }

    mutating func finish() throws -> DeepSeekStreamEvent? {
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true)
        if payload == "[DONE]" { return .done }
        guard let chunk = try? decoder.decode(DeepSeekStreamChunk.self, from: Data(payload.utf8)) else {
            throw InstantQuestionServiceFailure.invalidResponse(service: "DeepSeek")
        }
        guard let content = chunk.choices.first?.delta.content, !content.isEmpty else { return nil }
        return .delta(content)
    }
}

private struct DeepSeekStreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}

private struct DeepSeekChoice: Decodable {
    let message: DeepSeekResponseMessage
}
