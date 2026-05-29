import Foundation
import Combine

/// One terminal session NARC owns directly (its own PTY + child process).
/// Distinct from `ClaudeSession` (which only mirrors events from external hooks).
struct OwnedSession: Identifiable, Equatable {
    let id: UUID
    /// Initial label shown in the tab; updated when the child sets the terminal title.
    var displayTitle: String
    let executable: String
    let args: [String]
    let cwd: String?
    /// Set to false when the child process terminates. UI shows a gray dot then.
    var isAlive: Bool = true

    static func == (lhs: OwnedSession, rhs: OwnedSession) -> Bool {
        lhs.id == rhs.id
    }
}

/// Owns the list of in-NARC terminal sessions for the Dashboard.
/// All mutations must happen on the main thread (SwiftUI/AppKit constraint).
final class TerminalSessionManager: ObservableObject {
    @Published var sessions: [OwnedSession] = []

    /// Spawn a new session running `executable args` (defaults: login zsh).
    @discardableResult
    func newSession(
        title: String? = nil,
        executable: String = "/bin/zsh",
        args: [String] = ["-l"],
        cwd: String? = nil
    ) -> UUID {
        let id = UUID()
        let session = OwnedSession(
            id: id,
            displayTitle: title ?? defaultTitle(executable: executable, cwd: cwd),
            executable: executable,
            args: args,
            cwd: cwd
        )
        sessions.append(session)
        return id
    }

    /// Remove a session from the list. The pane view's `onExit` should already
    /// have fired (or will fire when SwiftUI unmounts the pane and SIGHUP propagates).
    func remove(_ id: UUID) {
        sessions.removeAll { $0.id == id }
    }

    func updateTitle(id: UUID, title: String) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].displayTitle = title
        }
    }

    func markDead(_ id: UUID) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].isAlive = false
        }
    }

    // MARK: -

    private func defaultTitle(executable: String, cwd: String?) -> String {
        if let cwd = cwd, !cwd.isEmpty {
            return (cwd as NSString).lastPathComponent
        }
        return (executable as NSString).lastPathComponent
    }
}
