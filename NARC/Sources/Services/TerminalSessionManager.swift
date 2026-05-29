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
    /// Monotonically increasing label counter. Reset only on app launch.
    private var nextSequenceNumber = 1

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
        sessions.removeAll { $0.id == id }
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
