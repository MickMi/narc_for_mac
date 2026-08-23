import Foundation

/// The explicit destination selected by the user in Quick Capture.
/// v2.0 deliberately does not infer this value with an external model.
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

/// Versioned on-disk payload for all v2.0 personal assistant data.
/// A computed ID satisfies the shared model contract without adding redundant
/// identity bytes to the encoded JSON.
struct AssistantSnapshot: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var todos: [TodoItem]
    var notes: [NoteItem]

    var id: Int { schemaVersion }

    init(
        schemaVersion: Int = AssistantSnapshot.currentSchemaVersion,
        todos: [TodoItem] = [],
        notes: [NoteItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.todos = todos
        self.notes = notes
    }
}
