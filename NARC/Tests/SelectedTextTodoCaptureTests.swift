import ApplicationServices
import Foundation
import Testing
@testable import NARC

@Test
func selectedTextEngineReadsDirectSelectionWithoutWalkingTheTree() {
    let backend = FakeSelectedTextAXAccess(
        focused: .value(1),
        nodes: [
            1: .init(selectedText: .value("Ship the selected task")),
        ]
    )
    let source = selectionSource()

    let result = SelectedTextReadEngine(access: backend).readSelection(from: source)

    #expect(result == .text(SelectedTextSnapshot(source: source, text: "Ship the selected task")))
    #expect(backend.parentReadCount == 0)
}

@Test
func selectedTextEngineUsesRangeAndBoundedParentFallback() {
    let backend = FakeSelectedTextAXAccess(
        focused: .value(1),
        nodes: [
            1: .init(parent: .value(2)),
            2: .init(
                selectedTextRange: .value(CFRange(location: 4, length: 12)),
                rangeText: .value("Browser text")
            ),
        ]
    )
    let source = selectionSource()

    let result = SelectedTextReadEngine(access: backend, maximumElementCount: 2)
        .readSelection(from: source)

    #expect(result == .text(SelectedTextSnapshot(source: source, text: "Browser text")))
    #expect(backend.parentReadCount == 1)
}

@Test
func selectedTextEngineSeparatesNoSelectionUnsupportedProtectedAndTransient() {
    let source = selectionSource()
    let noSelection = FakeSelectedTextAXAccess(
        focused: .value(1),
        nodes: [
            1: .init(
                selectedText: .value(""),
                selectedTextRange: .value(CFRange(location: 2, length: 0))
            ),
        ]
    )
    let unsupported = FakeSelectedTextAXAccess(
        focused: .value(1),
        nodes: [1: .init()]
    )
    let protected = FakeSelectedTextAXAccess(
        focused: .value(1),
        nodes: [1: .init(protection: .value(true))]
    )
    let transient = FakeSelectedTextAXAccess(
        focused: .value(1),
        nodes: [
            1: .init(selectedText: .issue(.transient(code: -25204))),
        ]
    )
    let whitespaceSelection = FakeSelectedTextAXAccess(
        focused: .value(1),
        nodes: [
            1: .init(
                selectedText: .value(" \n "),
                selectedTextRange: .value(CFRange(location: 0, length: 3)),
                rangeText: .value(" \n ")
            ),
        ]
    )

    #expect(
        SelectedTextReadEngine(access: noSelection).readSelection(from: source)
            == .failure(.noSelection)
    )
    #expect(
        SelectedTextReadEngine(access: unsupported).readSelection(from: source)
            == .failure(.unsupported)
    )
    #expect(
        SelectedTextReadEngine(access: protected).readSelection(from: source)
            == .failure(.protectedContent)
    )
    #expect(
        SelectedTextReadEngine(access: transient).readSelection(from: source)
            == .failure(.temporarilyUnavailable(code: -25204))
    )
    #expect(
        SelectedTextReadEngine(access: whitespaceSelection).readSelection(from: source)
            == .failure(.noSelection)
    )
}

@Test
func selectedTextEngineStopsAtConfiguredParentBound() {
    let backend = FakeSelectedTextAXAccess(
        focused: .value(1),
        nodes: [
            1: .init(parent: .value(2)),
            2: .init(parent: .value(3)),
            3: .init(selectedText: .value("Too deep")),
        ]
    )

    let result = SelectedTextReadEngine(access: backend, maximumElementCount: 2)
        .readSelection(from: selectionSource())

    #expect(result == .failure(.unsupported))
    #expect(backend.parentReadCount == 2)
}

@Test
func selectedTextEngineUsesTheTriggerTimeElementWithoutRefetchingFocus() {
    let backend = FakeSelectedTextAXAccess(
        focused: .value(1),
        nodes: [
            1: .init(selectedText: .value("Later focus")),
            2: .init(selectedText: .value("Trigger-time selection")),
        ]
    )
    let source = selectionSource()

    let result = SelectedTextReadEngine(access: backend)
        .readSelection(from: source, startingAt: 2)

    #expect(
        result == .text(.init(source: source, text: "Trigger-time selection"))
    )
    #expect(backend.focusedElementReadCount == 0)
}

@Test
func selectedTextEngineRejectsOversizedDirectAndRangeSelections() {
    let source = selectionSource()
    let directBackend = FakeSelectedTextAXAccess(
        focused: .value(1),
        nodes: [1: .init(selectedText: .value("123456"))]
    )
    let rangeBackend = FakeSelectedTextAXAccess(
        focused: .value(1),
        nodes: [
            1: .init(
                selectedTextRange: .value(CFRange(location: 0, length: 6)),
                rangeText: .value("123456")
            ),
        ]
    )

    #expect(
        SelectedTextReadEngine(
            access: directBackend,
            maximumSelectedTextUTF16Units: 5
        ).readSelection(from: source)
            == .failure(.selectionTooLarge(maximumUTF16Units: 5))
    )
    #expect(
        SelectedTextReadEngine(
            access: rangeBackend,
            maximumSelectedTextUTF16Units: 5
        ).readSelection(from: source)
            == .failure(.selectionTooLarge(maximumUTF16Units: 5))
    )
    #expect(rangeBackend.selectedTextReadCount == 0)
    #expect(rangeBackend.rangeStringReadCount == 0)
}

@Test
@MainActor
func axReaderLocksTheSourcePIDAndRetriesATransientFailureOnlyOnce() async {
    let originalSource = SelectedTextSource(processID: 7001, bundleIdentifier: "fixture.original")
    let laterSource = SelectedTextSource(processID: 7002, bundleIdentifier: "fixture.later")
    var sourceReads = 0
    var focusedElementPIDs: [pid_t] = []
    let recorder = RetryReadRecorder()
    let reader = AXSelectedTextReader(
        sourceProvider: {
            sourceReads += 1
            return sourceReads == 1 ? originalSource : laterSource
        },
        permissionCheck: { true },
        focusedElementCapture: { processID in
            focusedElementPIDs.append(processID)
            return .value(AXUIElementCreateSystemWide())
        },
        retryDelay: 0,
        readOperation: { source, _ in recorder.read(source) }
    )

    let result = await withCheckedContinuation { continuation in
        reader.readSelection { result in
            continuation.resume(returning: result)
        }
    }

    #expect(sourceReads == 1)
    #expect(focusedElementPIDs == [originalSource.processID])
    #expect(recorder.sources == [originalSource, originalSource])
    #expect(
        result == .text(SelectedTextSnapshot(source: originalSource, text: "Recovered selection"))
    )
}

@Test
func selectedTextPolicyUsesTheExactCharacterAndLineBoundaries() {
    let policy = SelectedTextTodoCapturePolicy()
    let source = selectionSource()
    let exactly240 = String(repeating: "x", count: 240)
    let over240 = String(repeating: "x", count: 241)
    let threeLines = "one\ntwo\n\nthree"
    let fourLines = "one\ntwo\nthree\nfour"

    #expect(
        policy.decision(for: .init(source: source, text: exactly240))
            == .save(.init(source: source, text: exactly240))
    )
    #expect(
        policy.decision(for: .init(source: source, text: over240))
            == .confirm(.init(source: source, text: over240))
    )
    #expect(
        policy.decision(for: .init(source: source, text: threeLines))
            == .save(.init(source: source, text: threeLines))
    )
    #expect(
        policy.decision(for: .init(source: source, text: fourLines))
            == .confirm(.init(source: source, text: fourLines))
    )
    #expect(
        policy.decision(for: .init(source: source, text: " \n\t "))
            == .reject(.noSelection)
    )
}

@Test
@MainActor
func coordinatorCreatesOneShortTodoAndRetainsOnlyItsUndoID() throws {
    let location = try makeSelectedTextStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let source = selectionSource()
    let reader = ImmediateSelectedTextReader(
        result: .text(.init(source: source, text: "  Selected task  "))
    )
    let store = AssistantStore(storageURL: location.file)
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    let coordinator = SelectedTextTodoCaptureCoordinator(
        reader: reader,
        store: store,
        now: { createdAt }
    )

    #expect(coordinator.capture())
    let token: SelectedTextTodoUndoToken
    guard case .saved(let savedToken) = coordinator.state else {
        Issue.record("Expected a successful selected-text capture")
        return
    }
    token = savedToken

    #expect(reader.readCount == 1)
    #expect(store.todos.count == 1)
    #expect(store.todos.first?.title == "Selected task")
    #expect(store.todos.first?.createdAt == createdAt)
    #expect(store.todos.first?.id == token.todoID)
}

@Test
@MainActor
func coordinatorDoesNotWriteLongTextBeforeConfirmationOrAfterCancellation() throws {
    let location = try makeSelectedTextStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let snapshot = SelectedTextSnapshot(
        source: selectionSource(),
        text: String(repeating: "long ", count: 60)
    )
    let reader = ImmediateSelectedTextReader(result: .text(snapshot))
    let store = AssistantStore(storageURL: location.file)
    let coordinator = SelectedTextTodoCaptureCoordinator(reader: reader, store: store)

    #expect(coordinator.capture())
    guard case .awaitingConfirmation(let pending) = coordinator.state else {
        Issue.record("Expected confirmation for long selected text")
        return
    }
    #expect(pending.text == snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines))
    #expect(store.todos.isEmpty)
    #expect(!coordinator.capture())
    #expect(coordinator.cancelPendingCapture())
    #expect(store.todos.isEmpty)

    #expect(coordinator.capture())
    #expect(coordinator.confirmPendingCapture())
    #expect(store.todos.count == 1)
}

@Test
@MainActor
func coordinatorIgnoresAnotherTriggerWhileTheReadIsOutstanding() throws {
    let location = try makeSelectedTextStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let reader = DeferredSelectedTextReader()
    let store = AssistantStore(storageURL: location.file)
    let coordinator = SelectedTextTodoCaptureCoordinator(reader: reader, store: store)

    #expect(coordinator.capture())
    #expect(!coordinator.capture())
    #expect(reader.readCount == 1)

    reader.complete(
        with: .text(.init(source: selectionSource(), text: "Only once"))
    )
    #expect(store.todos.map(\.title) == ["Only once"])
}

@Test
@MainActor
func coordinatorUndoDeletesTheExactCapturedUUIDAmongDuplicateTitles() throws {
    let location = try makeSelectedTextStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let store = AssistantStore(storageURL: location.file)
    let existingID = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
    #expect(store.createTodoItem(title: "Same title", id: existingID) != nil)

    let reader = ImmediateSelectedTextReader(
        result: .text(.init(source: selectionSource(), text: "Same title"))
    )
    let coordinator = SelectedTextTodoCaptureCoordinator(reader: reader, store: store)
    #expect(coordinator.capture())
    guard case .saved(let token) = coordinator.state else {
        Issue.record("Expected an Undo token")
        return
    }
    #expect(token.todoID != existingID)

    #expect(coordinator.undo(token))
    #expect(store.todos.map(\.id) == [existingID])
    #expect(coordinator.state == .undone(todoID: token.todoID))
}

@Test
@MainActor
func coordinatorSurfacesReadFailuresWithoutCreatingATodo() throws {
    let location = try makeSelectedTextStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let reader = ImmediateSelectedTextReader(result: .failure(.protectedContent))
    let store = AssistantStore(storageURL: location.file)
    let coordinator = SelectedTextTodoCaptureCoordinator(reader: reader, store: store)

    #expect(coordinator.capture())
    #expect(coordinator.state == .failed(.selection(.protectedContent)))
    #expect(store.todos.isEmpty)
}

@Test
@MainActor
func everySelectedTextReadFailureLeavesTodoStorageUntouched() throws {
    let failures: [SelectedTextReadFailure] = [
        .permissionRequired,
        .noFrontmostApplication,
        .narcIsFrontmost,
        .noFocusedElement,
        .noSelection,
        .selectionTooLarge(maximumUTF16Units: 65_536),
        .unsupported,
        .protectedContent,
        .temporarilyUnavailable(code: -25204),
    ]

    for failure in failures {
        let location = try makeSelectedTextStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let reader = ImmediateSelectedTextReader(result: .failure(failure))
        let store = AssistantStore(storageURL: location.file)
        let coordinator = SelectedTextTodoCaptureCoordinator(reader: reader, store: store)

        #expect(coordinator.capture())
        #expect(coordinator.state == .failed(.selection(failure)))
        #expect(store.todos.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: location.file.path))
    }
}

@Test
@MainActor
func coordinatorDoesNotPublishSuccessWhenTodoPersistenceFails() throws {
    let location = try makeSelectedTextStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let blockingParent = location.directory.appendingPathComponent("not-a-directory")
    #expect(FileManager.default.createFile(atPath: blockingParent.path, contents: Data()))
    let store = AssistantStore(
        storageURL: blockingParent.appendingPathComponent("assistant.json")
    )
    let reader = ImmediateSelectedTextReader(
        result: .text(.init(source: selectionSource(), text: "Must not appear"))
    )
    let coordinator = SelectedTextTodoCaptureCoordinator(reader: reader, store: store)

    #expect(coordinator.capture())
    guard case .failed(.save(let reason)) = coordinator.state,
          case .some(.saveFailed(_)) = reason else {
        Issue.record("Expected persistence failure instead of a saved state")
        return
    }
    #expect(store.todos.isEmpty)
}

private func selectionSource() -> SelectedTextSource {
    SelectedTextSource(processID: 4242, bundleIdentifier: "fixture.app")
}

private final class FakeSelectedTextAXAccess: SelectedTextAXAccessing {
    struct Node {
        var selectedText: SelectedTextAXRead<String> = .issue(.unsupported)
        var selectedTextRange: SelectedTextAXRead<CFRange> = .issue(.unsupported)
        var rangeText: SelectedTextAXRead<String> = .issue(.unsupported)
        var parent: SelectedTextAXRead<Int> = .issue(.noValue)
        var protection: SelectedTextAXRead<Bool> = .value(false)
    }

    let focused: SelectedTextAXRead<Int>
    let nodes: [Int: Node]
    private(set) var focusedElementReadCount = 0
    private(set) var selectedTextReadCount = 0
    private(set) var parentReadCount = 0
    private(set) var rangeStringReadCount = 0

    init(focused: SelectedTextAXRead<Int>, nodes: [Int: Node]) {
        self.focused = focused
        self.nodes = nodes
    }

    func focusedElement(for processID: pid_t) -> SelectedTextAXRead<Int> {
        focusedElementReadCount += 1
        return focused
    }

    func selectedText(of element: Int) -> SelectedTextAXRead<String> {
        selectedTextReadCount += 1
        return nodes[element]?.selectedText ?? .issue(.unsupported)
    }

    func selectedTextRange(of element: Int) -> SelectedTextAXRead<CFRange> {
        nodes[element]?.selectedTextRange ?? .issue(.unsupported)
    }

    func string(for range: CFRange, in element: Int) -> SelectedTextAXRead<String> {
        rangeStringReadCount += 1
        return nodes[element]?.rangeText ?? .issue(.unsupported)
    }

    func parent(of element: Int) -> SelectedTextAXRead<Int> {
        parentReadCount += 1
        return nodes[element]?.parent ?? .issue(.noValue)
    }

    func protectionStatus(of element: Int) -> SelectedTextAXRead<Bool> {
        nodes[element]?.protection ?? .value(false)
    }
}

private final class RetryReadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSources: [SelectedTextSource] = []

    var sources: [SelectedTextSource] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSources
    }

    func read(_ source: SelectedTextSource) -> SelectedTextReadResult {
        lock.lock()
        recordedSources.append(source)
        let attempt = recordedSources.count
        lock.unlock()

        if attempt == 1 {
            return .failure(.temporarilyUnavailable(code: -25204))
        }
        return .text(.init(source: source, text: "Recovered selection"))
    }
}

@MainActor
private final class ImmediateSelectedTextReader: SelectedTextReading {
    let result: SelectedTextReadResult
    private(set) var readCount = 0

    init(result: SelectedTextReadResult) {
        self.result = result
    }

    func readSelection(
        completion: @escaping @MainActor (SelectedTextReadResult) -> Void
    ) {
        readCount += 1
        completion(result)
    }
}

@MainActor
private final class DeferredSelectedTextReader: SelectedTextReading {
    private var pendingCompletion: (@MainActor (SelectedTextReadResult) -> Void)?
    private(set) var readCount = 0

    func readSelection(
        completion: @escaping @MainActor (SelectedTextReadResult) -> Void
    ) {
        readCount += 1
        pendingCompletion = completion
    }

    func complete(with result: SelectedTextReadResult) {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(result)
    }
}

private func makeSelectedTextStoreLocation() throws -> (directory: URL, file: URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("narc-selected-text-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return (
        directory,
        directory.appendingPathComponent("assistant-v1.json", isDirectory: false)
    )
}
