import Foundation
import Combine

/// One terminal session NARC owns directly (its own PTY + child process).
/// Distinct from `ClaudeSession` (which only mirrors events from external hooks).
struct OwnedSession: Identifiable, Equatable {
    let id: UUID
    /// User-set title (rename). When non-nil, takes precedence over `autoTitle`.
    /// Persists even when the shell pushes a new title via OSC sequences.
    var userTitle: String?
    /// Auto-detected title — initially "Terminal N", later overwritten by what
    /// the child shell announces via OSC sequences.
    var autoTitle: String
    let executable: String
    let args: [String]
    /// Working directory. Initial value is what we forked into; updated live as
    /// the shell sends OSC 7 (`hostCurrentDirectoryUpdate`).
    var cwd: String?
    /// When this tab was created. Used for "X minutes ago" display.
    let creationDate: Date
    /// False after the child process terminates. UI shows a gray dot then.
    var isAlive: Bool = true
    /// Live claude state from the most recent matching hook event, if any.
    /// Set by TerminalSessionManager subscribing to ClaudeSessionService and
    /// matching by NARC_SESSION_ID. nil means "no claude detected in this tab".
    var claude: ClaudeSession?
    /// Files Claude has touched in this session (Edit / Write / Read).
    /// Populated from ClaudioSession.fileHistory via applyClaudeUpdates.
    var touchedFiles: [FileChange] = []
    /// True when this tab's claude state changed while the user wasn't looking
    /// at it — driving the small red dot in the sidebar so the user can scan
    /// "what happened while I was on another tab". Cleared automatically when
    /// the user switches to this tab.
    var hasUnseenChange: Bool = false

    /// What to show in the tab. User rename wins, otherwise auto title.
    var displayTitle: String { userTitle ?? autoTitle }

    static func == (lhs: OwnedSession, rhs: OwnedSession) -> Bool {
        lhs.id == rhs.id
    }
}

/// Owns the list of in-NARC terminal sessions for the Dashboard.
/// All mutations must happen on the main thread (SwiftUI/AppKit constraint).
final class TerminalSessionManager: ObservableObject {
    @Published var sessions: [OwnedSession] = []
    /// The session currently visible in the right pane. Drives the unseen-change
    /// flag — when this changes, the just-selected session's flag clears.
    /// DashboardView keeps this in sync with its `@State selectedSessionId`.
    @Published var selectedId: UUID? {
        didSet { clearUnseen(for: selectedId) }
    }
    /// Monotonically increasing label counter. Reset only on app launch.
    private var nextSequenceNumber = 1
    /// Subscription to ClaudeSessionService, used to enrich tabs with claude state.
    private var claudeSubscription: AnyCancellable?

    /// Per-session callbacks that terminate the underlying PTY process.
    /// Registered by TerminalPaneView and invoked by `terminateAll()`.
    private var terminateCallbacks: [UUID: () -> Void] = [:]

    // MARK: - Session Logging

    private static let sessionLogDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".narc/sessions")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The log file URL for a given session. The file is created lazily when
    /// the first data arrives.
    static func logURL(for sessionId: UUID) -> URL {
        sessionLogDir.appendingPathComponent("\(sessionId.uuidString).log")
    }

    init(claudeService: ClaudeSessionService = .shared) {
        // Watch the shared claude state and project it onto our tabs by
        // matching NARC_SESSION_ID. Whenever a hook event arrives we re-fan
        // out to whichever OwnedSession owns that ID.
        claudeSubscription = claudeService.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] claudeMap in
                self?.applyClaudeUpdates(claudeMap)
            }
    }

    private func applyClaudeUpdates(_ claudeMap: [String: ClaudeSession]) {
        // Index by narcSessionId for O(N) merge.
        var byNarcId: [String: ClaudeSession] = [:]
        for (_, claude) in claudeMap {
            if let narcId = claude.narcSessionId {
                byNarcId[narcId] = claude
            }
        }
        for idx in sessions.indices {
            let key = sessions[idx].id.uuidString
            let oldStatus = sessions[idx].claude?.status
            let newClaude = byNarcId[key]
            // 冻结：service 删除已结束会话后 newClaude 变 nil，但 Tab 要保留"已结束"徽标。
            let freezeEnded = (newClaude == nil && oldStatus == .ended)
            if !freezeEnded {
                sessions[idx].claude = newClaude
                sessions[idx].touchedFiles = newClaude?.fileHistory ?? []
            }

            // Flag tabs whose status meaningfully changed while the user was
            // looking at a different tab. We deliberately ignore transitions
            // *into* "processing" / "running tool" because those fire dozens
            // of times per turn and would constantly bounce the dot.
            let newStatus = sessions[idx].claude?.status
            if let new = newStatus, new != oldStatus,
               sessions[idx].id != selectedId,
               new == .waitingForApproval || new == .waitingForInput || new == .ended {
                sessions[idx].hasUnseenChange = true
            }
        }
    }

    private func clearUnseen(for id: UUID?) {
        guard let id = id, let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        if sessions[idx].hasUnseenChange {
            sessions[idx].hasUnseenChange = false
        }
    }

    /// Spawn a new session running `executable args` (defaults: login zsh).
    /// Default title is `Terminal N` — shell-pushed titles or user renames
    /// override it later.
    @discardableResult
    func newSession(
        executable: String = "/bin/zsh",
        args: [String] = ["-l"],
        cwd: String? = nil
    ) -> UUID {
        let id = UUID()
        let session = OwnedSession(
            id: id,
            userTitle: nil,
            autoTitle: "Terminal \(nextSequenceNumber)",
            executable: executable,
            args: args,
            cwd: cwd,
            creationDate: Date()
        )
        nextSequenceNumber += 1
        sessions.append(session)
        return id
    }

    /// Remove a session from the list. The pane view's `onExit` should already
    /// have fired (or will fire when SwiftUI unmounts the pane and SIGHUP propagates).
    func remove(_ id: UUID) {
        terminateCallbacks.removeValue(forKey: id)
        sessions.removeAll { $0.id == id }
    }

    /// Reorder sessions (drag-to-reorder in the tab list).
    func moveSession(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Chrome-style Drag State

    /// The session currently being dragged, if any. nil when idle.
    @Published var draggingSessionId: UUID? = nil
    /// Current translation of the drag gesture (relative to the row's origin).
    @Published var draggingTranslation: CGSize = .zero
    /// The index where the dragged item would be inserted. nil when not hovering
    /// over a valid drop position.
    @Published var dropTargetIndex: Int? = nil

    func beginDrag(_ id: UUID) {
        draggingSessionId = id
        draggingTranslation = .zero
    }

    func updateDrag(translation: CGSize, targetIndex: Int?) {
        draggingTranslation = translation
        dropTargetIndex = targetIndex
    }

    func endDrag(commit: Bool) {
        if commit,
           let id = draggingSessionId,
           let target = dropTargetIndex,
           let from = sessions.firstIndex(where: { $0.id == id }) {
            if target != from {
                let s = sessions.remove(at: from)
                sessions.insert(s, at: target)
            }
        }
        draggingSessionId = nil
        draggingTranslation = .zero
        dropTargetIndex = nil
    }

    /// Register a closure that terminates the underlying PTY process for a session.
    /// Called by TerminalPaneView when the view appears.
    func registerTerminateCallback(for sessionId: UUID, _ callback: @escaping () -> Void) {
        terminateCallbacks[sessionId] = callback
    }

    /// Kill all terminal processes. Called when the user chooses "关闭终端" in
    /// the Workspace close-confirmation alert.
    func terminateAll() {
        for (_, callback) in terminateCallbacks {
            callback()
        }
        terminateCallbacks.removeAll()
        sessions.removeAll()
    }

    /// User explicitly renamed the tab. Persists across PTY title changes.
    /// Clearing (empty string) reverts to auto-detected title.
    func rename(id: UUID, title: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[idx].userTitle = trimmed.isEmpty ? nil : trimmed
    }

    /// Auto-update title from the PTY (OSC sequences). Doesn't override userTitle.
    func updateAutoTitle(id: UUID, title: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].autoTitle = title
    }

    /// Auto-update cwd from the PTY (OSC 7).
    func updateCwd(id: UUID, cwd: String?) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].cwd = cwd
    }

    func markDead(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isAlive = false
    }
}
