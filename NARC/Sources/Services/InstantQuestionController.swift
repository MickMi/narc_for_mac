import AppKit
import Combine
import Foundation

@MainActor
final class InstantQuestionController: ObservableObject {
    enum AttachmentFailure: LocalizedError, Equatable {
        case empty
        case tooLarge
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .empty:
                return "这张图片没有可读取的内容。"
            case .tooLarge:
                return "图片不能超过 32 MB。"
            case .unsupportedFormat:
                return "请选择 JPEG、PNG、GIF 或 WebP 图片。"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case searching
        case answering
        case failed
    }

    @Published var draft = ""
    @Published private(set) var messages: [InstantQuestionMessage] = []
    @Published private(set) var sources: [InstantQuestionSource] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var savedRecordID: UUID?
    @Published private(set) var imageAttachment: InstantQuestionImageAttachment?
    @Published private(set) var streamingAnswer = ""
    @Published private(set) var connectionCheckMessage: String?
    @Published private(set) var isCheckingConnection = false

    let credentials: InstantQuestionCredentialManager
    let store: InstantQuestionStore

    private let service: InstantQuestionAnswering
    private var requestTask: Task<Void, Never>?
    private var streamFlushTask: Task<Void, Never>?
    private var pendingStreamText = ""
    private var activeRequestID: UUID?

    init(
        credentials: InstantQuestionCredentialManager,
        store: InstantQuestionStore,
        service: InstantQuestionAnswering = DeepSeekQuestionService()
    ) {
        self.credentials = credentials
        self.store = store
        self.service = service
    }

    var isBusy: Bool { phase == .searching || phase == .answering }
    var canSend: Bool {
        credentials.isReady && !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canSave: Bool {
        !isBusy && messages.last?.role == .assistant
    }
    var latestAnswer: String? {
        messages.last(where: { $0.role == .assistant })?.content
    }

    func sendDraft() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy else { return }
        do {
            let currentCredentials = try credentials.credentials()
            draft = ""
            errorMessage = nil
            let userMessage = InstantQuestionMessage(role: .user, content: question)
            messages.append(userMessage)
            phase = .answering
            let requestMessages = messages
            let requestAttachment = imageAttachment
            let requestID = UUID()
            activeRequestID = requestID
            streamingAnswer = ""
            pendingStreamText = ""
            streamFlushTask?.cancel()
            streamFlushTask = nil
            requestTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let reply = try await service.streamAnswer(
                        messages: requestMessages,
                        attachment: requestAttachment,
                        credentials: currentCredentials,
                        onChunk: { [weak self] chunk in
                            guard let self else { return }
                            await self.receiveStreamChunk(chunk, requestID: requestID)
                        }
                    )
                    guard !Task.isCancelled, self.activeRequestID == requestID else { return }
                    self.flushStreamText(for: requestID)
                    let merged = Self.mergedSources(self.sources, reply.sources)
                    self.sources = merged.all
                    self.messages.append(
                        InstantQuestionMessage(
                            role: .assistant,
                            content: reply.answer,
                            sourceIDs: merged.currentIDs
                        )
                    )
                    // Images belong only to the completed round. Preserve any
                    // replacement attachment prepared while the request ran.
                    if self.imageAttachment == requestAttachment {
                        self.removeImage()
                    }
                    self.streamingAnswer = ""
                    self.activeRequestID = nil
                    self.phase = .idle
                    self.requestTask = nil
                } catch is CancellationError {
                    if self.activeRequestID == requestID { self.requestTask = nil }
                } catch {
                    guard !Task.isCancelled, self.activeRequestID == requestID else { return }
                    self.flushStreamText(for: requestID)
                    self.activeRequestID = nil
                    self.phase = .failed
                    self.errorMessage = error.localizedDescription
                    self.requestTask = nil
                }
            }
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func saveCurrent(now: Date = Date()) -> Bool {
        guard canSave,
              let firstQuestion = messages.first(where: { $0.role == .user }) else { return false }
        let existing = savedRecordID.flatMap { id in store.records.first(where: { $0.id == id }) }
        let record = SavedInstantQuestion(
            id: existing?.id ?? UUID(),
            title: String(firstQuestion.content.prefix(80)),
            messages: messages,
            sources: sources,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        guard store.save(record) else {
            errorMessage = store.lastError?.localizedDescription
            return false
        }
        savedRecordID = record.id
        errorMessage = nil
        return true
    }

    func copyLatestAnswer() {
        guard let latestAnswer else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latestAnswer, forType: .string)
    }

    func validateConnection() {
        guard !isCheckingConnection else { return }
        do {
            let currentCredentials = try credentials.credentials()
            isCheckingConnection = true
            connectionCheckMessage = "正在验证 DeepSeek…"
            Task { [weak self] in
                guard let self else { return }
                do {
                    _ = try await service.answer(
                        messages: [
                            InstantQuestionMessage(
                                role: .user,
                                content: "NARC 连接测试：请只回复“连接正常”。"
                            ),
                        ],
                        attachment: nil,
                        credentials: currentCredentials
                    )
                    guard !Task.isCancelled else { return }
                    self.connectionCheckMessage = "连接正常：DeepSeek 可用。"
                    self.isCheckingConnection = false
                } catch {
                    guard !Task.isCancelled else { return }
                    self.connectionCheckMessage = error.localizedDescription
                    self.isCheckingConnection = false
                }
            }
        } catch {
            connectionCheckMessage = error.localizedDescription
        }
    }

    /// Clears only the in-memory question shown in the search window.
    /// Explicitly saved records remain in `store`.
    func clearCurrent() {
        requestTask?.cancel()
        requestTask = nil
        streamFlushTask?.cancel()
        streamFlushTask = nil
        pendingStreamText = ""
        activeRequestID = nil
        streamingAnswer = ""
        draft = ""
        messages = []
        sources = []
        phase = .idle
        errorMessage = nil
        savedRecordID = nil
        imageAttachment = nil
    }

    func attachImage(name: String, mediaType: String, data: Data) throws {
        guard !data.isEmpty else { throw AttachmentFailure.empty }
        guard data.count <= InstantQuestionImageAttachment.maximumByteCount else {
            throw AttachmentFailure.tooLarge
        }
        guard InstantQuestionImageAttachment.supportedMediaTypes.contains(mediaType) else {
            throw AttachmentFailure.unsupportedFormat
        }
        imageAttachment = InstantQuestionImageAttachment(
            name: name,
            mediaType: mediaType,
            data: data
        )
        errorMessage = nil
    }

    func removeImage() {
        imageAttachment = nil
    }

    func report(_ error: Error) {
        phase = .failed
        errorMessage = error.localizedDescription
    }

    private func receiveStreamChunk(_ chunk: String, requestID: UUID) {
        guard activeRequestID == requestID, phase == .answering else { return }
        pendingStreamText += chunk
        guard streamFlushTask == nil else { return }
        streamFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            self?.flushStreamText(for: requestID)
        }
    }

    private func flushStreamText(for requestID: UUID) {
        streamFlushTask?.cancel()
        streamFlushTask = nil
        guard activeRequestID == requestID, !pendingStreamText.isEmpty else { return }
        streamingAnswer += pendingStreamText
        pendingStreamText = ""
    }

    private static func mergedSources(
        _ existing: [InstantQuestionSource],
        _ additions: [InstantQuestionSource]
    ) -> (all: [InstantQuestionSource], currentIDs: [UUID]) {
        var result = existing
        var idsByURL = Dictionary(uniqueKeysWithValues: existing.map { ($0.url.absoluteString, $0.id) })
        var currentIDs: [UUID] = []
        for source in additions {
            if let existingID = idsByURL[source.url.absoluteString] {
                currentIDs.append(existingID)
            } else {
                result.append(source)
                idsByURL[source.url.absoluteString] = source.id
                currentIDs.append(source.id)
            }
        }
        return (result, currentIDs)
    }
}
