import Foundation

/// The explicit destination selected when an Inbox item is organized.
/// v2 deliberately does not infer this value with an external model.
enum CaptureKind: String, Codable, CaseIterable, Identifiable {
    case todo
    case note

    var id: String { rawValue }
}

enum TodoPriority: Int, Codable, CaseIterable, Identifiable {
    case high = 0, normal = 1, low = 2
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .high: return "高优先级"
        case .normal: return "普通优先级"
        case .low: return "低优先级"
        }
    }
}

/// A lightweight personal task captured inside NARC.
struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var deferredUntil: Date?
    var priority: TodoPriority
    var dueAt: Date?
    var isNext: Bool

    var isCompleted: Bool { completedAt != nil }

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        completedAt: Date? = nil,
        deferredUntil: Date? = nil,
        priority: TodoPriority = .normal,
        dueAt: Date? = nil,
        isNext: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = completedAt
        self.deferredUntil = deferredUntil
        self.priority = priority
        self.dueAt = dueAt
        self.isNext = isNext
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, completedAt, deferredUntil, priority, dueAt, isNext
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        deferredUntil = try values.decodeIfPresent(Date.self, forKey: .deferredUntil)
        priority = try values.decodeIfPresent(TodoPriority.self, forKey: .priority) ?? .normal
        dueAt = try values.decodeIfPresent(Date.self, forKey: .dueAt)
        isNext = try values.decodeIfPresent(Bool.self, forKey: .isNext) ?? false
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

/// Versioned on-disk payload for all personal assistant data.
/// A computed ID satisfies the shared model contract without adding redundant
/// identity bytes to the encoded JSON.
struct AssistantSnapshot: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 4

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
