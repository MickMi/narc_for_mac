import Cocoa
import Combine
import Foundation

/// Immutable identity of the app that owned focus when the shortcut fired.
///
/// The process ID is captured before any asynchronous work or NARC UI appears,
/// so later focus changes cannot redirect the read to another application.
struct SelectedTextSource: Equatable, Sendable {
    let processID: pid_t
    let bundleIdentifier: String?
}

/// A point-in-time selection returned by the source application.
struct SelectedTextSnapshot: Equatable, Sendable {
    let source: SelectedTextSource
    let text: String
}

enum SelectedTextReadFailure: Error, Equatable, Sendable {
    case permissionRequired
    case noFrontmostApplication
    case narcIsFrontmost
    case noFocusedElement
    case noSelection
    case selectionTooLarge(maximumUTF16Units: Int)
    case unsupported
    case protectedContent
    case temporarilyUnavailable(code: Int32)
}

enum SelectedTextReadResult: Equatable, Sendable {
    case text(SelectedTextSnapshot)
    case failure(SelectedTextReadFailure)
}

/// Normalized answers from the C Accessibility API. Keeping AXError handling at
/// this boundary makes the traversal engine deterministic in unit tests.
enum SelectedTextAXIssue: Equatable, Sendable {
    case noValue
    case unsupported
    case permissionRequired
    case transient(code: Int32)
}

enum SelectedTextAXRead<Value> {
    case value(Value)
    case issue(SelectedTextAXIssue)
}

/// Minimal platform seam used by the bounded selection traversal.
protocol SelectedTextAXAccessing {
    associatedtype Element

    func focusedElement(for processID: pid_t) -> SelectedTextAXRead<Element>
    func selectedText(of element: Element) -> SelectedTextAXRead<String>
    func selectedTextRange(of element: Element) -> SelectedTextAXRead<CFRange>
    func string(for range: CFRange, in element: Element) -> SelectedTextAXRead<String>
    func parent(of element: Element) -> SelectedTextAXRead<Element>
    func protectionStatus(of element: Element) -> SelectedTextAXRead<Bool>
}

/// Reads only the focused element and a small number of ancestors. It never
/// walks the full accessibility tree, which bounds both latency and the amount
/// of another application's UI that NARC inspects.
struct SelectedTextReadEngine<Access: SelectedTextAXAccessing> {
    private let access: Access
    private let maximumElementCount: Int
    private let maximumSelectedTextUTF16Units: Int

    init(
        access: Access,
        maximumElementCount: Int = 8,
        maximumSelectedTextUTF16Units: Int = 65_536
    ) {
        self.access = access
        self.maximumElementCount = max(1, maximumElementCount)
        self.maximumSelectedTextUTF16Units = max(1, maximumSelectedTextUTF16Units)
    }

    func readSelection(from source: SelectedTextSource) -> SelectedTextReadResult {
        let focusedElement: Access.Element
        switch access.focusedElement(for: source.processID) {
        case .value(let element):
            focusedElement = element
        case .issue(.permissionRequired):
            return .failure(.permissionRequired)
        case .issue(.transient(let code)):
            return .failure(.temporarilyUnavailable(code: code))
        case .issue(.noValue), .issue(.unsupported):
            return .failure(.noFocusedElement)
        }

        return readSelection(from: source, startingAt: focusedElement)
    }

    /// Continue from the element captured at the hotkey boundary. Production
    /// uses this entry point so a later focus change inside the same app cannot
    /// redirect the asynchronous text read.
    func readSelection(
        from source: SelectedTextSource,
        startingAt focusedElement: Access.Element
    ) -> SelectedTextReadResult {

        var currentElement: Access.Element? = focusedElement
        var sawSelectionCapability = false
        var sawUnreadableNonEmptyRange = false

        for _ in 0..<maximumElementCount {
            guard let element = currentElement else { break }

            switch access.protectionStatus(of: element) {
            case .value(true):
                return .failure(.protectedContent)
            case .value(false), .issue(.noValue), .issue(.unsupported):
                break
            case .issue(.permissionRequired):
                return .failure(.permissionRequired)
            case .issue(.transient(let code)):
                return .failure(.temporarilyUnavailable(code: code))
            }

            // Read the lightweight range metadata first when the control
            // exposes it. This rejects pathological selections before asking
            // AXStringForRange or AXSelectedText to materialize their body.
            var selectedRange: CFRange?
            var deferredRangeTransientCode: Int32?
            switch access.selectedTextRange(of: element) {
            case .value(let range):
                sawSelectionCapability = true
                guard range.length <= maximumSelectedTextUTF16Units else {
                    return .failure(.selectionTooLarge(
                        maximumUTF16Units: maximumSelectedTextUTF16Units
                    ))
                }
                if range.length > 0 {
                    selectedRange = range
                }
            case .issue(.noValue):
                sawSelectionCapability = true
            case .issue(.unsupported):
                break
            case .issue(.permissionRequired):
                return .failure(.permissionRequired)
            case .issue(.transient(let code)):
                // Direct AXSelectedText may still be available. Preserve the
                // transient result only if neither standard path succeeds.
                deferredRangeTransientCode = code
            }

            var deferredDirectTransientCode: Int32?
            switch access.selectedText(of: element) {
            case .value(let text):
                sawSelectionCapability = true
                if Self.hasUsableText(text) {
                    guard text.utf16.count <= maximumSelectedTextUTF16Units else {
                        return .failure(.selectionTooLarge(
                            maximumUTF16Units: maximumSelectedTextUTF16Units
                        ))
                    }
                    return .text(SelectedTextSnapshot(source: source, text: text))
                }
            case .issue(.noValue):
                // AXNoValue means the attribute exists but currently has no
                // selection. Keep walking because web containers often expose
                // the real selection on an ancestor.
                sawSelectionCapability = true
            case .issue(.unsupported):
                break
            case .issue(.permissionRequired):
                return .failure(.permissionRequired)
            case .issue(.transient(let code)):
                deferredDirectTransientCode = code
            }

            if let range = selectedRange {
                switch access.string(for: range, in: element) {
                case .value(let text):
                    if Self.hasUsableText(text) {
                        guard text.utf16.count <= maximumSelectedTextUTF16Units else {
                            return .failure(.selectionTooLarge(
                                maximumUTF16Units: maximumSelectedTextUTF16Units
                            ))
                        }
                        return .text(SelectedTextSnapshot(source: source, text: text))
                    }
                case .issue(.noValue), .issue(.unsupported):
                    sawUnreadableNonEmptyRange = true
                case .issue(.permissionRequired):
                    return .failure(.permissionRequired)
                case .issue(.transient(let code)):
                    return .failure(.temporarilyUnavailable(code: code))
                }
            }

            if let code = deferredDirectTransientCode ?? deferredRangeTransientCode {
                return .failure(.temporarilyUnavailable(code: code))
            }

            switch access.parent(of: element) {
            case .value(let parent):
                currentElement = parent
            case .issue(.permissionRequired):
                return .failure(.permissionRequired)
            case .issue(.transient(let code)):
                return .failure(.temporarilyUnavailable(code: code))
            case .issue(.noValue), .issue(.unsupported):
                currentElement = nil
            }
        }

        if sawUnreadableNonEmptyRange {
            return .failure(.unsupported)
        }
        return .failure(sawSelectionCapability ? .noSelection : .unsupported)
    }

    private static func hasUsableText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// AXUIElement is an immutable remote object reference and can be used from a
/// different thread after capture. The actual reads remain serialized on the
/// reader's dedicated queue.
struct LockedSelectedTextAXElement: @unchecked Sendable {
    let element: AXUIElement
}

/// System implementation backed only by documented Accessibility attributes:
/// AXFocusedUIElement, AXSelectedText, AXSelectedTextRange, AXStringForRange,
/// AXParent, AXSubrole, and AXContainsProtectedContent.
struct SystemSelectedTextAXAccess: SelectedTextAXAccessing, Sendable {
    typealias Element = AXUIElement

    private let messagingTimeout: Float

    init(messagingTimeout: Float = 0.35) {
        self.messagingTimeout = messagingTimeout
    }

    func focusedElement(for processID: pid_t) -> SelectedTextAXRead<AXUIElement> {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)

        switch elementAttribute(kAXFocusedUIElementAttribute as CFString, of: application) {
        case .value(let element):
            return lockedElement(element, to: processID)
        case .issue(.noValue), .issue(.unsupported):
            // Some applications expose focus only on the system-wide object.
            // Validate the PID so a focus change cannot redirect the capture.
            let systemWide = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
            switch elementAttribute(kAXFocusedUIElementAttribute as CFString, of: systemWide) {
            case .value(let element):
                return lockedElement(element, to: processID)
            case .issue(let issue):
                return .issue(issue)
            }
        case .issue(let issue):
            return .issue(issue)
        }
    }

    func selectedText(of element: AXUIElement) -> SelectedTextAXRead<String> {
        stringAttribute(kAXSelectedTextAttribute as CFString, of: element)
    }

    func selectedTextRange(of element: AXUIElement) -> SelectedTextAXRead<CFRange> {
        switch rawAttribute(kAXSelectedTextRangeAttribute as CFString, of: element) {
        case .value(let value):
            guard CFGetTypeID(value) == AXValueGetTypeID() else {
                return .issue(.transient(code: AXError.failure.rawValue))
            }
            let axValue = value as! AXValue
            guard AXValueGetType(axValue) == .cfRange else {
                return .issue(.transient(code: AXError.failure.rawValue))
            }
            var range = CFRange(location: 0, length: 0)
            guard AXValueGetValue(axValue, .cfRange, &range),
                  range.location >= 0,
                  range.length >= 0 else {
                return .issue(.transient(code: AXError.failure.rawValue))
            }
            return .value(range)
        case .issue(let issue):
            return .issue(issue)
        }
    }

    func string(for range: CFRange, in element: AXUIElement) -> SelectedTextAXRead<String> {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return .issue(.transient(code: AXError.failure.rawValue))
        }

        var value: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard error == .success else { return .issue(Self.issue(for: error)) }
        guard let text = value as? String else {
            return .issue(.transient(code: AXError.failure.rawValue))
        }
        return .value(text)
    }

    func parent(of element: AXUIElement) -> SelectedTextAXRead<AXUIElement> {
        elementAttribute(kAXParentAttribute as CFString, of: element)
    }

    func protectionStatus(of element: AXUIElement) -> SelectedTextAXRead<Bool> {
        var deferredIssue: SelectedTextAXIssue?

        switch stringAttribute(kAXSubroleAttribute as CFString, of: element) {
        case .value(let subrole) where subrole == (kAXSecureTextFieldSubrole as String):
            return .value(true)
        case .value, .issue(.noValue), .issue(.unsupported):
            break
        case .issue(.permissionRequired):
            return .issue(.permissionRequired)
        case .issue(let issue):
            deferredIssue = issue
        }

        switch boolAttribute("AXContainsProtectedContent" as CFString, of: element) {
        case .value(let isProtected):
            return .value(isProtected)
        case .issue(.noValue), .issue(.unsupported):
            if let deferredIssue { return .issue(deferredIssue) }
            return .value(false)
        case .issue(let issue):
            return .issue(issue)
        }
    }

    private func rawAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> SelectedTextAXRead<CFTypeRef> {
        var value: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return .issue(Self.issue(for: error)) }
        guard let value else { return .issue(.noValue) }
        return .value(value)
    }

    private func lockedElement(
        _ element: AXUIElement,
        to processID: pid_t
    ) -> SelectedTextAXRead<AXUIElement> {
        var elementProcessID: pid_t = 0
        let error = AXUIElementGetPid(element, &elementProcessID)
        guard error == .success else { return .issue(Self.issue(for: error)) }
        guard elementProcessID == processID else { return .issue(.noValue) }
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return .value(element)
    }

    private func elementAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> SelectedTextAXRead<AXUIElement> {
        switch rawAttribute(attribute, of: element) {
        case .value(let value):
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return .issue(.transient(code: AXError.failure.rawValue))
            }
            return .value(value as! AXUIElement)
        case .issue(let issue):
            return .issue(issue)
        }
    }

    private func stringAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> SelectedTextAXRead<String> {
        switch rawAttribute(attribute, of: element) {
        case .value(let value):
            guard let string = value as? String else {
                return .issue(.transient(code: AXError.failure.rawValue))
            }
            return .value(string)
        case .issue(let issue):
            return .issue(issue)
        }
    }

    private func boolAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> SelectedTextAXRead<Bool> {
        switch rawAttribute(attribute, of: element) {
        case .value(let value):
            guard let bool = value as? Bool else {
                return .issue(.transient(code: AXError.failure.rawValue))
            }
            return .value(bool)
        case .issue(let issue):
            return .issue(issue)
        }
    }

    private static func issue(for error: AXError) -> SelectedTextAXIssue {
        switch error {
        case .noValue:
            return .noValue
        case .attributeUnsupported, .parameterizedAttributeUnsupported, .notImplemented:
            return .unsupported
        case .apiDisabled:
            return .permissionRequired
        default:
            return .transient(code: error.rawValue)
        }
    }
}

@MainActor
protocol SelectedTextReading: AnyObject {
    func readSelection(
        completion: @escaping @MainActor (SelectedTextReadResult) -> Void
    )
}

/// Captures the frontmost PID synchronously, then performs bounded AX IPC on a
/// serial worker. Only a transient AX failure is retried, and only once.
@MainActor
final class AXSelectedTextReader: SelectedTextReading {
    private let sourceProvider: @MainActor () -> SelectedTextSource?
    private let permissionCheck: () -> Bool
    private let focusedElementCapture: @MainActor (pid_t) -> SelectedTextAXRead<AXUIElement>
    private let retryDelay: TimeInterval
    private let readOperation: @Sendable (
        SelectedTextSource,
        LockedSelectedTextAXElement
    ) -> SelectedTextReadResult
    private let workQueue: DispatchQueue

    init(
        sourceProvider: @escaping @MainActor () -> SelectedTextSource? = AXSelectedTextReader.frontmostSource,
        permissionCheck: @escaping () -> Bool = AXIsProcessTrusted,
        focusedElementCapture: @escaping @MainActor (pid_t) -> SelectedTextAXRead<AXUIElement> = {
            processID in
            // This single bounded AX lookup is intentionally synchronous at
            // the trigger boundary; later text IPC runs off the main thread.
            SystemSelectedTextAXAccess(messagingTimeout: 0.12)
                .focusedElement(for: processID)
        },
        retryDelay: TimeInterval = 0.025,
        workQueue: DispatchQueue = DispatchQueue(
            label: "com.mickmi.narc.selected-text",
            qos: .userInitiated
        ),
        readOperation: (@Sendable (
            SelectedTextSource,
            LockedSelectedTextAXElement
        ) -> SelectedTextReadResult)? = nil
    ) {
        self.sourceProvider = sourceProvider
        self.permissionCheck = permissionCheck
        self.focusedElementCapture = focusedElementCapture
        self.retryDelay = max(0, retryDelay)
        self.workQueue = workQueue

        if let readOperation {
            self.readOperation = readOperation
        } else {
            self.readOperation = { source, lockedElement in
                SelectedTextReadEngine(access: SystemSelectedTextAXAccess())
                    .readSelection(from: source, startingAt: lockedElement.element)
            }
        }
    }

    func readSelection(
        completion: @escaping @MainActor (SelectedTextReadResult) -> Void
    ) {
        guard permissionCheck() else {
            completion(.failure(.permissionRequired))
            return
        }
        guard let source = sourceProvider() else {
            completion(.failure(.noFrontmostApplication))
            return
        }
        guard source.processID != ProcessInfo.processInfo.processIdentifier else {
            completion(.failure(.narcIsFrontmost))
            return
        }

        let focusedElement: AXUIElement
        switch focusedElementCapture(source.processID) {
        case .value(let element):
            focusedElement = element
        case .issue(.permissionRequired):
            completion(.failure(.permissionRequired))
            return
        case .issue(.transient(let code)):
            completion(.failure(.temporarilyUnavailable(code: code)))
            return
        case .issue(.noValue), .issue(.unsupported):
            completion(.failure(.noFocusedElement))
            return
        }
        let lockedElement = LockedSelectedTextAXElement(element: focusedElement)

        // Capture all actor-isolated properties before leaving the main actor.
        let operation = readOperation
        let retryDelay = retryDelay
        let queue = workQueue

        queue.async {
            let firstResult = operation(source, lockedElement)
            guard case .failure(.temporarilyUnavailable) = firstResult else {
                Task { @MainActor in completion(firstResult) }
                return
            }

            queue.asyncAfter(deadline: .now() + retryDelay) {
                let finalResult = operation(source, lockedElement)
                Task { @MainActor in completion(finalResult) }
            }
        }
    }

    private static func frontmostSource() -> SelectedTextSource? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return SelectedTextSource(
            processID: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier
        )
    }
}

enum SelectedTextTodoCaptureDecision: Equatable, Sendable {
    case save(SelectedTextSnapshot)
    case confirm(SelectedTextSnapshot)
    case reject(SelectedTextReadFailure)
}

/// Pure policy for the boundary between low-friction capture and an explicit
/// long-text confirmation. Exactly 240 characters and exactly three non-empty
/// logical lines still save directly; exceeding either limit requires consent.
struct SelectedTextTodoCapturePolicy: Equatable, Sendable {
    let directCharacterLimit: Int
    let directNonEmptyLineLimit: Int

    init(directCharacterLimit: Int = 240, directNonEmptyLineLimit: Int = 3) {
        self.directCharacterLimit = max(1, directCharacterLimit)
        self.directNonEmptyLineLimit = max(1, directNonEmptyLineLimit)
    }

    func decision(for snapshot: SelectedTextSnapshot) -> SelectedTextTodoCaptureDecision {
        let normalized = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .reject(.noSelection) }

        let normalizedSnapshot = SelectedTextSnapshot(
            source: snapshot.source,
            text: normalized
        )
        let nonEmptyLineCount = normalized
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count

        if normalized.count > directCharacterLimit
            || nonEmptyLineCount > directNonEmptyLineLimit {
            return .confirm(normalizedSnapshot)
        }
        return .save(normalizedSnapshot)
    }
}

struct SelectedTextTodoUndoToken: Equatable, Sendable {
    let todoID: UUID
}

enum SelectedTextTodoCaptureFailure: Equatable {
    case selection(SelectedTextReadFailure)
    case save(AssistantStoreFailure?)
    case undo(todoID: UUID, reason: AssistantStoreFailure?)
}

enum SelectedTextTodoCaptureState: Equatable {
    case idle
    case reading
    case awaitingConfirmation(SelectedTextSnapshot)
    case saving
    case saved(SelectedTextTodoUndoToken)
    case failed(SelectedTextTodoCaptureFailure)
    case undone(todoID: UUID)
}

/// Main-actor state machine joining an asynchronous selection snapshot to the
/// single AssistantStore. It retains text only while confirmation is pending;
/// successful state retains only the exact UUID needed for Undo.
@MainActor
final class SelectedTextTodoCaptureCoordinator: ObservableObject {
    @Published private(set) var state: SelectedTextTodoCaptureState = .idle

    private let reader: any SelectedTextReading
    private let store: AssistantStore
    private let policy: SelectedTextTodoCapturePolicy
    private let now: () -> Date

    init(
        reader: any SelectedTextReading,
        store: AssistantStore,
        policy: SelectedTextTodoCapturePolicy = SelectedTextTodoCapturePolicy(),
        now: @escaping () -> Date = Date.init
    ) {
        self.reader = reader
        self.store = store
        self.policy = policy
        self.now = now
    }

    /// Returns false when a read, confirmation, or write is already in flight.
    @discardableResult
    func capture() -> Bool {
        switch state {
        case .reading, .awaitingConfirmation, .saving:
            return false
        case .idle, .saved, .failed, .undone:
            break
        }

        state = .reading
        reader.readSelection { [weak self] result in
            self?.handle(result)
        }
        return true
    }

    @discardableResult
    func confirmPendingCapture() -> Bool {
        guard case .awaitingConfirmation(let snapshot) = state else {
            return false
        }
        return persist(snapshot)
    }

    @discardableResult
    func cancelPendingCapture() -> Bool {
        guard case .awaitingConfirmation = state else { return false }
        state = .idle
        return true
    }

    /// Deletes only the Todo identified by this capture's immutable token.
    @discardableResult
    func undo(_ token: SelectedTextTodoUndoToken) -> Bool {
        if store.deleteTodo(id: token.todoID) {
            state = .undone(todoID: token.todoID)
            return true
        }

        state = .failed(.undo(todoID: token.todoID, reason: store.lastError))
        return false
    }

    func clearFeedback() {
        switch state {
        case .saved, .failed, .undone:
            state = .idle
        case .idle, .reading, .awaitingConfirmation, .saving:
            break
        }
    }

    private func handle(_ result: SelectedTextReadResult) {
        guard case .reading = state else { return }

        switch result {
        case .failure(let failure):
            state = .failed(.selection(failure))
        case .text(let snapshot):
            switch policy.decision(for: snapshot) {
            case .reject(let failure):
                state = .failed(.selection(failure))
            case .confirm(let normalizedSnapshot):
                state = .awaitingConfirmation(normalizedSnapshot)
            case .save(let normalizedSnapshot):
                _ = persist(normalizedSnapshot)
            }
        }
    }

    @discardableResult
    private func persist(_ snapshot: SelectedTextSnapshot) -> Bool {
        state = .saving
        guard let item = store.createTodoItem(title: snapshot.text, now: now()) else {
            state = .failed(.save(store.lastError))
            return false
        }

        state = .saved(SelectedTextTodoUndoToken(todoID: item.id))
        return true
    }
}
