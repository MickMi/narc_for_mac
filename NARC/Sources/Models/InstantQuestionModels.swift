import Foundation

enum InstantQuestionRole: String, Codable {
    case user
    case assistant
}

struct InstantQuestionMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: InstantQuestionRole
    let content: String
    let createdAt: Date
    let sourceIDs: [UUID]
    /// nil for legacy / offline answers; only server search events set true.
    let webSearchUsed: Bool?

    init(
        id: UUID = UUID(),
        role: InstantQuestionRole,
        content: String,
        createdAt: Date = Date(),
        sourceIDs: [UUID] = [],
        webSearchUsed: Bool? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.sourceIDs = sourceIDs
        self.webSearchUsed = webSearchUsed
    }
}

struct InstantQuestionSource: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let url: URL
    let snippet: String

    init(id: UUID = UUID(), title: String, url: URL, snippet: String) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

struct SavedInstantQuestion: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var messages: [InstantQuestionMessage]
    var sources: [InstantQuestionSource]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        messages: [InstantQuestionMessage],
        sources: [InstantQuestionSource],
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.sources = sources
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

struct InstantQuestionSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var records: [SavedInstantQuestion]

    init(
        schemaVersion: Int = InstantQuestionSnapshot.currentSchemaVersion,
        records: [SavedInstantQuestion] = []
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}

struct InstantQuestionCredentials: Equatable {
    let deepSeekAPIKey: String
}

struct InstantQuestionReply: Equatable {
    let answer: String
    let sources: [InstantQuestionSource]
    var webSearchUsed: Bool? = nil
}

struct InstantQuestionImageAttachment: Equatable {
    static let maximumByteCount = 32 * 1_024 * 1_024
    static let supportedMediaTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"]

    let name: String
    let mediaType: String
    let data: Data
}
