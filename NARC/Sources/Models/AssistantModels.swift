import Foundation

/// The explicit destination selected when an Inbox item is organized.
/// v2 deliberately does not infer this value with an external model.
enum CaptureKind: String, Codable, CaseIterable, Identifiable {
    case todo
    case note

    var id: String { rawValue }
}

/// A lightweight personal task captured inside NARC.
struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    var isCompleted: Bool { completedAt != nil }

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = completedAt
    }
}

/// A plain-text note captured inside NARC.
struct NoteItem: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// An unclassified thought captured before the user decides whether it belongs
/// in Todo or Notes.
struct InboxItem: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// Versioned on-disk payload for all v2.0 personal assistant data.
/// A computed ID satisfies the shared model contract without adding redundant
/// identity bytes to the encoded JSON.
struct AssistantSnapshot: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    var todos: [TodoItem]
    var notes: [NoteItem]
    var inboxItems: [InboxItem]

    var id: Int { schemaVersion }

    init(
        schemaVersion: Int = AssistantSnapshot.currentSchemaVersion,
        todos: [TodoItem] = [],
        notes: [NoteItem] = [],
        inboxItems: [InboxItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.todos = todos
        self.notes = notes
        self.inboxItems = inboxItems
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case todos
        case notes
        case inboxItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        todos = try container.decode([TodoItem].self, forKey: .todos)
        notes = try container.decode([NoteItem].self, forKey: .notes)
        if schemaVersion == 1 {
            inboxItems = try container.decodeIfPresent([InboxItem].self, forKey: .inboxItems) ?? []
        } else {
            inboxItems = try container.decode([InboxItem].self, forKey: .inboxItems)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(todos, forKey: .todos)
        try container.encode(notes, forKey: .notes)
        try container.encode(inboxItems, forKey: .inboxItems)
    }
}
