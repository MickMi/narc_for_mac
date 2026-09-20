import Foundation
import Testing
@testable import NARC

@Test
@MainActor
func assistantStorePersistsTodoAndNoteAcrossReload() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let store = AssistantStore(storageURL: location.file)

    #expect(store.createTodo(title: "  Ship the assistant plan  ", now: createdAt))
    #expect(store.createNote(content: "  Keep Workspace as-is.  ", now: createdAt))
    #expect(store.todos.map(\.title) == ["Ship the assistant plan"])
    #expect(store.notes.map(\.content) == ["Keep Workspace as-is."])
    #expect(FileManager.default.fileExists(atPath: location.file.path))

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.todos == store.todos)
    #expect(reloaded.notes == store.notes)
    #expect(reloaded.inboxItems.isEmpty)
    #expect(reloaded.lastError == nil)
}

@Test
@MainActor
func assistantStoreReturnsCommittedTodoAndUndoDeletesOnlyItsExactUUID() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000031"))
    let capturedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000032"))
    let store = AssistantStore(storageURL: location.file)

    let first = try #require(
        store.createTodoItem(title: "Same title", id: firstID, now: createdAt)
    )
    let captured = try #require(
        store.createTodoItem(
            title: "Same title",
            id: capturedID,
            now: createdAt.addingTimeInterval(1)
        )
    )

    #expect(first.id == firstID)
    #expect(captured.id == capturedID)
    #expect(store.deleteTodo(id: captured.id))
    #expect(store.todos.map(\.id) == [firstID])

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.todos.map(\.id) == [firstID])
    #expect(reloaded.todos.map(\.title) == ["Same title"])
}

@Test
@MainActor
func assistantStoreDoesNotPublishTodoDeletionWhenSaveFails() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)
    let item = try #require(store.createTodoItem(title: "Keep exact Todo"))
    let originalTodos = store.todos

    try FileManager.default.removeItem(at: location.directory)
    try Data("blocks-directory-recreation".utf8).write(to: location.directory)

    #expect(!store.deleteTodo(id: item.id))
    guard case .saveFailed = store.lastError else {
        Issue.record("Expected a failed Todo deletion to surface saveFailed")
        return
    }
    #expect(store.todos == originalTodos)
}

@Test
@MainActor
func assistantStorePersistsSortsAndDeletesInboxItems() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
    let newerDate = Date(timeIntervalSince1970: 1_700_000_100)
    let store = AssistantStore(storageURL: location.file)

    #expect(store.captureInbox("  First thought  ", now: olderDate))
    #expect(store.captureInbox("Second thought", now: newerDate))
    #expect(store.inboxItems.map(\.content) == ["First thought", "Second thought"])
    #expect(store.recentInboxItems.map(\.content) == ["Second thought", "First thought"])

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.inboxItems == store.inboxItems)
    #expect(reloaded.recentInboxItems.map(\.content) == ["Second thought", "First thought"])

    let firstID = try #require(reloaded.inboxItems.first?.id)
    #expect(reloaded.deleteInbox(id: firstID))

    let afterDeletion = AssistantStore(storageURL: location.file)
    #expect(afterDeletion.inboxItems.map(\.content) == ["Second thought"])
}

@Test
@MainActor
func inboxCaptureStatePersistsDraftUntilASuccessfulSave() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)
    var completionCount = 0
    let captureState = InboxCaptureState(store: store) {
        completionCount += 1
    }

    captureState.updateDraft("  Keep this draft  ")
    #expect(captureState.draft == "  Keep this draft  ")
    #expect(captureState.submit())
    #expect(captureState.draft.isEmpty)
    #expect(captureState.successMessage == "已存入随手箱")
    #expect(completionCount == 1)
    #expect(store.inboxItems.map(\.content) == ["Keep this draft"])
}

@Test
@MainActor
func inboxCaptureStateKeepsTextAndDoesNotCompleteWhenPersistenceFails() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let corruptData = Data("{not-valid-json".utf8)
    try corruptData.write(to: location.file, options: .atomic)
    let store = AssistantStore(storageURL: location.file)
    var completionCount = 0
    let captureState = InboxCaptureState(store: store) {
        completionCount += 1
    }

    captureState.updateDraft("Do not lose this")
    #expect(!captureState.submit())
    #expect(captureState.draft == "Do not lose this")
    #expect(captureState.validationMessage != nil)
    #expect(completionCount == 0)
    #expect(try Data(contentsOf: location.file) == corruptData)
}

@Test
@MainActor
func inboxCaptureStateCreatesTodoDirectlyAndCompletesAfterSave() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)
    var completionCount = 0
    let captureState = InboxCaptureState(store: store) {
        completionCount += 1
    }

    captureState.updateDraft("  Handle this directly  ")
    #expect(captureState.submitTodo())
    #expect(captureState.draft.isEmpty)
    #expect(captureState.successMessage == "已创建 Todo")
    #expect(completionCount == 1)
    #expect(store.todos.map(\.title) == ["Handle this directly"])
    #expect(store.inboxItems.isEmpty)

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.todos.map(\.id) == store.todos.map(\.id))
    #expect(reloaded.todos.map(\.title) == ["Handle this directly"])
    #expect(reloaded.todos.first?.completedAt == nil)
    #expect(reloaded.todos.first?.deferredUntil == nil)
    #expect(reloaded.inboxItems.isEmpty)
}

@Test
@MainActor
func inboxCaptureStateKeepsTextWhenDirectTodoPersistenceFails() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let corruptData = Data("{not-valid-json".utf8)
    try corruptData.write(to: location.file, options: .atomic)
    let store = AssistantStore(storageURL: location.file)
    var completionCount = 0
    let captureState = InboxCaptureState(store: store) {
        completionCount += 1
    }

    captureState.updateDraft("Do not lose this Todo")
    #expect(!captureState.submitTodo())
    #expect(captureState.draft == "Do not lose this Todo")
    #expect(captureState.validationMessage != nil)
    #expect(completionCount == 0)
    #expect(store.todos.isEmpty)
    #expect(store.inboxItems.isEmpty)
    #expect(try Data(contentsOf: location.file) == corruptData)
}

@Test
@MainActor
func assistantStorePersistsTodoCompletion() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let completedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let store = AssistantStore(storageURL: location.file)

    #expect(store.createTodo(title: "Verify persistence", now: createdAt))
    let todoID = try #require(store.todos.first?.id)
    #expect(store.setTodoCompleted(id: todoID, completed: true, now: completedAt))
    #expect(store.incompleteTodos.isEmpty)
    #expect(store.completedTodos.first?.completedAt == completedAt)

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.todos.first?.isCompleted == true)
    #expect(reloaded.todos.first?.completedAt == completedAt)
}

@Test
@MainActor
func assistantStorePersistsDeferralAndHonorsAvailabilityBoundary() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let deferredAt = createdAt.addingTimeInterval(60)
    let deferredUntil = createdAt.addingTimeInterval(3_600)
    let store = AssistantStore(storageURL: location.file)

    #expect(store.createTodo(title: "Return after an hour", now: createdAt))
    let todoID = try #require(store.todos.first?.id)
    #expect(store.setTodoDeferred(id: todoID, until: deferredUntil, now: deferredAt))
    #expect(store.todos.first?.deferredUntil == deferredUntil)
    #expect(store.todos.first?.updatedAt == deferredAt)
    #expect(store.availableTodos(now: deferredUntil.addingTimeInterval(-1)).isEmpty)
    #expect(store.availableTodos(now: deferredUntil).map(\.id) == [todoID])

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.todos.first?.deferredUntil == deferredUntil)
    #expect(reloaded.availableTodos(now: deferredUntil.addingTimeInterval(-1)).isEmpty)
    #expect(reloaded.availableTodos(now: deferredUntil).map(\.id) == [todoID])
}

@Test
@MainActor
func assistantStoreCompletionTransitionsClearDeferral() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let deferredUntil = createdAt.addingTimeInterval(3_600)
    let completedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let pendingID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let snapshot = AssistantSnapshot(
        todos: [
            TodoItem(
                id: completedID,
                title: "Reopen me",
                createdAt: createdAt,
                completedAt: createdAt,
                deferredUntil: deferredUntil
            ),
            TodoItem(
                id: pendingID,
                title: "Finish me",
                createdAt: createdAt,
                deferredUntil: deferredUntil
            ),
        ]
    )
    try makeAssistantEncoder().encode(snapshot).write(to: location.file, options: .atomic)
    let store = AssistantStore(storageURL: location.file)

    let changedAt = createdAt.addingTimeInterval(120)
    #expect(store.setTodoCompleted(id: completedID, completed: false, now: changedAt))
    #expect(store.setTodoCompleted(id: pendingID, completed: true, now: changedAt))
    #expect(store.todos.first { $0.id == completedID }?.completedAt == nil)
    #expect(store.todos.first { $0.id == completedID }?.deferredUntil == nil)
    #expect(store.todos.first { $0.id == pendingID }?.completedAt == changedAt)
    #expect(store.todos.first { $0.id == pendingID }?.deferredUntil == nil)

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.todos == store.todos)
}

@Test
@MainActor
func assistantStoreDoesNotPublishDeferralWhenSaveFails() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let store = AssistantStore(storageURL: location.file)
    #expect(store.createTodo(title: "Keep me available", now: createdAt))
    let originalTodos = store.todos
    let todoID = try #require(originalTodos.first?.id)

    try FileManager.default.removeItem(at: location.directory)
    try Data("blocks-directory-recreation".utf8).write(to: location.directory)

    #expect(
        !store.setTodoDeferred(
            id: todoID,
            until: createdAt.addingTimeInterval(3_600),
            now: createdAt.addingTimeInterval(60)
        )
    )
    guard case .saveFailed = store.lastError else {
        Issue.record("Expected failed deferral persistence to surface saveFailed")
        return
    }
    #expect(store.todos == originalTodos)
    #expect(store.availableTodos(now: createdAt.addingTimeInterval(60)).map(\.id) == [todoID])
}

@Test
@MainActor
func assistantStoreDoesNotPublishCompletionWhenSaveFails() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let store = AssistantStore(storageURL: location.file)
    #expect(store.createTodo(title: "Remain incomplete", now: createdAt))
    let originalTodos = store.todos
    let todoID = try #require(originalTodos.first?.id)

    try FileManager.default.removeItem(at: location.directory)
    try Data("blocks-directory-recreation".utf8).write(to: location.directory)

    #expect(
        !store.setTodoCompleted(
            id: todoID,
            completed: true,
            now: createdAt.addingTimeInterval(60)
        )
    )
    guard case .saveFailed = store.lastError else {
        Issue.record("Expected failed completion persistence to surface saveFailed")
        return
    }
    #expect(store.todos == originalTodos)
    #expect(store.availableTodos(now: createdAt.addingTimeInterval(60)).map(\.id) == [todoID])
}

@Test
@MainActor
func assistantStoreNextTodoHandlesEmptyAndSingleCandidate() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let store = AssistantStore(storageURL: location.file)
    #expect(store.nextTodo(after: nil, now: now) == nil)

    #expect(store.createTodo(title: "Only Todo", now: now))
    let onlyTodo = try #require(store.todos.first)
    #expect(store.nextTodo(after: nil, now: now)?.id == onlyTodo.id)
    #expect(store.nextTodo(after: onlyTodo.id, now: now)?.id == onlyTodo.id)
    #expect(store.nextTodo(after: UUID(), now: now)?.id == onlyTodo.id)
}

@Test
@MainActor
func assistantStoreNextTodoCyclesAndSkipsUnavailableItems() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let oldestDate = Date(timeIntervalSince1970: 1_700_000_000)
    let middleDate = oldestDate.addingTimeInterval(60)
    let newestDate = oldestDate.addingTimeInterval(120)
    let now = newestDate.addingTimeInterval(60)
    let store = AssistantStore(storageURL: location.file)
    #expect(store.createTodo(title: "Oldest", now: oldestDate))
    #expect(store.createTodo(title: "Middle", now: middleDate))
    #expect(store.createTodo(title: "Newest", now: newestDate))

    let oldest = try #require(store.todos.first { $0.title == "Oldest" })
    let middle = try #require(store.todos.first { $0.title == "Middle" })
    let newest = try #require(store.todos.first { $0.title == "Newest" })
    #expect(store.availableTodos(now: now).map(\.id) == [newest.id, middle.id, oldest.id])
    #expect(store.nextTodo(after: newest.id, now: now)?.id == middle.id)
    #expect(store.nextTodo(after: middle.id, now: now)?.id == oldest.id)
    #expect(store.nextTodo(after: oldest.id, now: now)?.id == newest.id)

    #expect(
        store.setTodoDeferred(
            id: middle.id,
            until: now.addingTimeInterval(3_600),
            now: now
        )
    )
    #expect(store.setTodoCompleted(id: oldest.id, completed: true, now: now))
    #expect(store.availableTodos(now: now).map(\.id) == [newest.id])
    #expect(store.nextTodo(after: middle.id, now: now)?.id == newest.id)
}

@Test
@MainActor
func assistantStoreNextTodoDoesNotTouchStorageOrPublishedState() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
    let newerDate = olderDate.addingTimeInterval(60)
    let store = AssistantStore(storageURL: location.file)
    #expect(store.createTodo(title: "Older", now: olderDate))
    #expect(store.createTodo(title: "Newer", now: newerDate))

    let beforeData = try Data(contentsOf: location.file)
    let beforeAttributes = try FileManager.default.attributesOfItem(atPath: location.file.path)
    let beforeFileNumber = beforeAttributes[.systemFileNumber] as? NSNumber
    let beforeTodos = store.todos
    let firstID = try #require(store.availableTodos(now: newerDate).first?.id)

    #expect(store.nextTodo(after: firstID, now: newerDate) != nil)

    let afterData = try Data(contentsOf: location.file)
    let afterAttributes = try FileManager.default.attributesOfItem(atPath: location.file.path)
    let afterFileNumber = afterAttributes[.systemFileNumber] as? NSNumber
    #expect(afterData == beforeData)
    #expect(afterFileNumber == beforeFileNumber)
    #expect(store.todos == beforeTodos)
    #expect(store.lastError == nil)
}

@Test
@MainActor
func assistantStoreUsesUUIDToStabilizeEqualCreationDates() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let lowerID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let higherID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let snapshot = AssistantSnapshot(
        todos: [
            TodoItem(id: higherID, title: "Higher", createdAt: createdAt),
            TodoItem(id: lowerID, title: "Lower", createdAt: createdAt),
        ]
    )
    try makeAssistantEncoder().encode(snapshot).write(to: location.file, options: .atomic)
    let store = AssistantStore(storageURL: location.file)

    #expect(store.incompleteTodos.map(\.id) == [lowerID, higherID])
    #expect(store.availableTodos(now: createdAt).map(\.id) == [lowerID, higherID])
    #expect(store.nextTodo(after: lowerID, now: createdAt)?.id == higherID)
    #expect(store.nextTodo(after: higherID, now: createdAt)?.id == lowerID)
}

@Test
@MainActor
func assistantStoreRejectsBlankContentWithoutCreatingAFile() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)

    #expect(!store.createTodo(title: " \n\t "))
    #expect(store.lastError == .blankContent)
    #expect(store.todos.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: location.file.path))

    store.clearError()
    #expect(!store.createNote(content: "   "))
    #expect(store.lastError == .blankContent)
    #expect(store.notes.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: location.file.path))

    store.clearError()
    #expect(!store.captureInbox(" \n\t "))
    #expect(store.lastError == .blankContent)
    #expect(store.inboxItems.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: location.file.path))
}

@Test
@MainActor
func assistantStoreDoesNotOverwriteCorruptData() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let corruptData = Data("{not-valid-json".utf8)
    try corruptData.write(to: location.file, options: .atomic)

    let store = AssistantStore(storageURL: location.file)
    guard case .loadFailed = store.lastError else {
        Issue.record("Expected corrupt data to produce a load failure")
        return
    }

    #expect(!store.createTodo(title: "Must not replace the file"))
    #expect(store.lastError == .writesBlockedAfterLoadFailure)
    #expect(try Data(contentsOf: location.file) == corruptData)
}

@Test
@MainActor
func assistantStoreSearchesAndDeletesNotesPersistently() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)
    #expect(store.createNote(content: "Alpha decision"))
    #expect(store.createNote(content: "Beta follow-up"))

    let matches = store.searchNotes(query: "ALPHA")
    #expect(matches.count == 1)
    #expect(matches.first?.content == "Alpha decision")

    let noteID = try #require(matches.first?.id)
    #expect(store.deleteNote(id: noteID))
    #expect(store.searchNotes(query: "alpha").isEmpty)

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.notes.map(\.content) == ["Beta follow-up"])
}

@Test
@MainActor
func assistantStoreLoadsV1AndWritesCurrentSchemaWithoutLosingData() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let todoID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
    let legacyTodo = LegacyTodoItem(
        id: todoID,
        title: "Existing Todo",
        createdAt: createdAt,
        updatedAt: createdAt,
        completedAt: nil
    )
    let expectedTodo = TodoItem(
        id: todoID,
        title: legacyTodo.title,
        createdAt: createdAt
    )
    let legacyNote = NoteItem(content: "Existing Note", createdAt: createdAt)
    let legacySnapshot = LegacyAssistantSnapshot(
        schemaVersion: 1,
        todos: [legacyTodo],
        notes: [legacyNote]
    )
    try makeAssistantEncoder().encode(legacySnapshot).write(to: location.file, options: .atomic)

    let store = AssistantStore(storageURL: location.file)
    #expect(store.todos == [expectedTodo])
    #expect(store.notes == [legacyNote])
    #expect(store.inboxItems.isEmpty)
    #expect(store.lastError == nil)

    #expect(store.captureInbox("First Inbox", now: createdAt.addingTimeInterval(60)))

    let migrated = try makeAssistantDecoder().decode(
        AssistantSnapshot.self,
        from: Data(contentsOf: location.file)
    )
    #expect(migrated.schemaVersion == AssistantSnapshot.currentSchemaVersion)
    #expect(migrated.todos == [expectedTodo])
    #expect(migrated.notes == [legacyNote])
    #expect(migrated.inboxItems.map(\.content) == ["First Inbox"])
}

@Test
@MainActor
func assistantStoreLoadsV2AndWritesCurrentSchemaWithoutLosingData() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let todoID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
    let legacyTodo = LegacyTodoItem(
        id: todoID,
        title: "Existing v2 Todo",
        createdAt: createdAt,
        updatedAt: createdAt,
        completedAt: nil
    )
    let legacyNote = NoteItem(content: "Existing v2 Note", createdAt: createdAt)
    let legacyInbox = InboxItem(content: "Existing v2 Inbox", createdAt: createdAt)
    let legacySnapshot = LegacyAssistantSnapshotV2(
        schemaVersion: 2,
        todos: [legacyTodo],
        notes: [legacyNote],
        inboxItems: [legacyInbox]
    )
    try makeAssistantEncoder().encode(legacySnapshot).write(to: location.file, options: .atomic)

    let store = AssistantStore(storageURL: location.file)
    #expect(store.todos.first?.id == todoID)
    #expect(store.todos.first?.title == legacyTodo.title)
    #expect(store.todos.first?.deferredUntil == nil)
    #expect(store.notes == [legacyNote])
    #expect(store.inboxItems == [legacyInbox])
    #expect(store.lastError == nil)

    let deferredUntil = createdAt.addingTimeInterval(3_600)
    #expect(
        store.setTodoDeferred(
            id: todoID,
            until: deferredUntil,
            now: createdAt.addingTimeInterval(60)
        )
    )

    let migrated = try makeAssistantDecoder().decode(
        AssistantSnapshot.self,
        from: Data(contentsOf: location.file)
    )
    #expect(migrated.schemaVersion == AssistantSnapshot.currentSchemaVersion)
    #expect(migrated.todos.first?.id == todoID)
    #expect(migrated.todos.first?.deferredUntil == deferredUntil)
    #expect(migrated.notes == [legacyNote])
    #expect(migrated.inboxItems == [legacyInbox])
}

@Test
@MainActor
func assistantStoreConvertsInboxToTodoAndNoteAtomically() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let todoCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let noteCreatedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let convertedAt = Date(timeIntervalSince1970: 1_700_000_200)
    let store = AssistantStore(storageURL: location.file)

    #expect(store.captureInbox("Plan release", now: todoCreatedAt))
    #expect(store.captureInbox("Remember this decision", now: noteCreatedAt))
    let todoInbox = try #require(store.inboxItems.first { $0.content == "Plan release" })
    let noteInbox = try #require(store.inboxItems.first { $0.content == "Remember this decision" })

    #expect(store.convertInbox(id: todoInbox.id, to: .todo, now: convertedAt))
    #expect(store.convertInbox(id: noteInbox.id, to: .note, now: convertedAt))
    #expect(store.inboxItems.isEmpty)
    #expect(store.todos.first?.id == todoInbox.id)
    #expect(store.todos.first?.title == todoInbox.content)
    #expect(store.todos.first?.createdAt == todoCreatedAt)
    #expect(store.todos.first?.updatedAt == convertedAt)
    #expect(store.notes.first?.id == noteInbox.id)
    #expect(store.notes.first?.content == noteInbox.content)
    #expect(store.notes.first?.createdAt == noteCreatedAt)
    #expect(store.notes.first?.updatedAt == convertedAt)

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.inboxItems.isEmpty)
    #expect(reloaded.todos == store.todos)
    #expect(reloaded.notes == store.notes)
}

@Test
@MainActor
func assistantStoreLeavesInboxUntouchedWhenConversionTargetIsMissing() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)
    #expect(store.captureInbox("Keep me"))
    let originalInbox = store.inboxItems

    #expect(!store.convertInbox(id: UUID(), to: .todo))
    #expect(store.inboxItems == originalInbox)
    #expect(store.todos.isEmpty)
    #expect(store.notes.isEmpty)
}

@Test
@MainActor
func assistantStoreDoesNotPublishPartialConversionWhenSaveFails() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)
    #expect(store.captureInbox("Do not lose me"))
    let item = try #require(store.inboxItems.first)

    try FileManager.default.removeItem(at: location.directory)
    try Data("blocks-directory-recreation".utf8).write(to: location.directory)

    #expect(!store.convertInbox(id: item.id, to: .todo))
    guard case .saveFailed = store.lastError else {
        Issue.record("Expected a failed atomic write to surface saveFailed")
        return
    }
    #expect(store.inboxItems == [item])
    #expect(store.todos.isEmpty)
    #expect(store.notes.isEmpty)
}

@Test
@MainActor
func assistantStoreBlocksWritesForFutureSchema() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let futureVersion = AssistantSnapshot.currentSchemaVersion + 1
    let futureSnapshot = AssistantSnapshot(
        schemaVersion: futureVersion,
        inboxItems: [InboxItem(content: "Future data")]
    )
    let originalData = try makeAssistantEncoder().encode(futureSnapshot)
    try originalData.write(to: location.file, options: .atomic)

    let store = AssistantStore(storageURL: location.file)
    #expect(store.lastError == .unsupportedSchema(futureVersion))
    #expect(!store.captureInbox("Must not overwrite future data"))
    #expect(store.lastError == .writesBlockedAfterLoadFailure)
    #expect(try Data(contentsOf: location.file) == originalData)
}

@Test
@MainActor
func assistantStorePlanningSortsByExplicitNextThenPriorityThenDeadline() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let items = [
        TodoItem(title: "normal due", createdAt: now, dueAt: now),
        TodoItem(title: "high late", createdAt: now, priority: .high, dueAt: now.addingTimeInterval(600)),
        TodoItem(title: "high early", createdAt: now, priority: .high, dueAt: now),
        TodoItem(title: "high undated", createdAt: now, priority: .high),
        TodoItem(title: "explicit low", createdAt: now, priority: .low, isNext: true),
        TodoItem(title: "completed", createdAt: now, completedAt: now, priority: .high),
        TodoItem(title: "deferred", createdAt: now, deferredUntil: now.addingTimeInterval(300), priority: .high),
    ]
    try makeAssistantEncoder().encode(AssistantSnapshot(todos: items)).write(to: location.file)
    let store = AssistantStore(storageURL: location.file)
    #expect(store.availableTodos(now: now).map(\.title) == ["explicit low", "high early", "high late", "high undated", "normal due"])
    #expect(store.updateTodoPlanning(id: items[0].id, priority: .normal, dueAt: now, isNext: true, now: now))
    #expect(store.todos.filter(\.isNext).map(\.id) == [items[0].id])
    #expect(store.availableTodos(now: now).first?.id == items[0].id)
    #expect(AssistantStore(storageURL: location.file).todos == store.todos)
    #expect(store.setTodoCompleted(id: items[0].id, completed: true, now: now))
    #expect(!store.todos.contains { $0.isNext })
    #expect(store.availableTodos(now: now).first?.id == items[2].id)
    #expect(store.updateTodoPlanning(id: items[6].id, priority: .low, dueAt: nil, isNext: true, now: now))
    #expect(store.availableTodos(now: now).first?.id == items[6].id)
    #expect(store.todos.first(where: { $0.id == items[6].id })?.deferredUntil == nil)
}

@Test
@MainActor
func assistantStorePlanningSaveFailureDoesNotPublishPartialNextChoice() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let store = AssistantStore(storageURL: location.file)
    let first = try #require(store.createTodoItem(title: "first"))
    let second = try #require(store.createTodoItem(title: "second"))
    #expect(store.updateTodoPlanning(id: first.id, priority: .high, dueAt: nil, isNext: true))
    let original = store.todos
    try FileManager.default.removeItem(at: location.directory)
    try Data("blocked".utf8).write(to: location.directory)
    #expect(!store.updateTodoPlanning(id: second.id, priority: .low, dueAt: Date(), isNext: true))
    #expect(store.todos == original)
    #expect(store.lastError != nil)
}

@Test
@MainActor
func assistantStoreLoadsV3WithoutWritingThenMigratesPlanningAndPreservesContent() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let todo = TodoItem(title: "legacy", createdAt: now, deferredUntil: now.addingTimeInterval(3600))
    let note = NoteItem(content: "keep note", createdAt: now)
    let inbox = InboxItem(content: "keep inbox", createdAt: now)
    let data = try makeAssistantEncoder().encode(AssistantSnapshot(schemaVersion: 3, todos: [todo], notes: [note], inboxItems: [inbox]))
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var rows = try #require(json["todos"] as? [[String: Any]])
    rows[0].removeValue(forKey: "priority")
    rows[0].removeValue(forKey: "isNext")
    rows[0].removeValue(forKey: "dueAt")
    json["todos"] = rows
    let legacy = try JSONSerialization.data(withJSONObject: json)
    try legacy.write(to: location.file)
    let store = AssistantStore(storageURL: location.file)
    #expect(store.lastError == nil)
    #expect(store.todos == [todo])
    #expect(try Data(contentsOf: location.file) == legacy)
    #expect(store.updateTodoPlanning(id: todo.id, priority: .high, dueAt: now, isNext: false, now: now))
    let snapshot = try makeAssistantDecoder().decode(AssistantSnapshot.self, from: Data(contentsOf: location.file))
    #expect(snapshot.schemaVersion == 4)
    #expect(snapshot.todos.first?.priority == .high)
    #expect(snapshot.todos.first?.dueAt == now)
    #expect(snapshot.todos.first?.deferredUntil == todo.deferredUntil)
    #expect(snapshot.notes == [note])
    #expect(snapshot.inboxItems == [inbox])
}

private struct LegacyAssistantSnapshot: Encodable {
    let schemaVersion: Int
    let todos: [LegacyTodoItem]
    let notes: [NoteItem]
}

private struct LegacyTodoItem: Encodable {
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
}

private struct LegacyAssistantSnapshotV2: Encodable {
    let schemaVersion: Int
    let todos: [LegacyTodoItem]
    let notes: [NoteItem]
    let inboxItems: [InboxItem]
}

private func makeAssistantEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

private func makeAssistantDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func makeAssistantTestLocation() throws -> (directory: URL, file: URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("narc-assistant-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return (
        directory,
        directory.appendingPathComponent("assistant-v1.json", isDirectory: false)
    )
}
