import Cocoa
import Combine

/// Monitors Claude Code sessions via NARC's own Unix socket.
/// Independent from ClaudeIsland — NARC registers its own hook.
///
/// Triggers strong notification only at key decision points:
/// - PermissionRequest: high-risk action needs approval
/// - Stop: Claude finished a turn, waiting for user input
/// - StopFailure: Claude encountered an error
/// - Stale: no events for >60s, may be stuck
class ClaudeSessionService: ObservableObject {

    static let shared = ClaudeSessionService()

    // MARK: - Published State

    @Published var sessions: [String: ClaudeSession] = [:]
    @Published var pendingApprovals: [PendingApproval] = []
    @Published var notifications: [ClaudeNotification] = []

    /// Set briefly to a session ID when that session emits a Stop/StopFailure
    /// event. The workspace UI reads this to flash a "task done" banner. Cleared
    /// automatically after `completedFlashDuration` seconds.
    @Published var completedFlash: String? = nil
    private let completedFlashDuration: TimeInterval = 6.0
    private var completedFlashTimer: Timer?

    // MARK: - Socket

    private let socketPath = "/tmp/narc-claude.sock"
    private var serverSocket: Int32 = -1
    private var isListening = false
    private let listenQueue = DispatchQueue(label: "com.narc.claude-socket", qos: .userInitiated)
    private var staleTimer: Timer?
    private let staleThreshold: TimeInterval = 60.0

    /// Callback for key events that need user attention
    var onAttentionNeeded: ((AttentionReason) -> Void)?

    enum AttentionReason {
        case permissionRequest
        case stopped(sessionId: String)
        case error(sessionId: String, message: String?)
        case stale(sessionId: String)
    }

    // MARK: - Init

    private init() {}

    // MARK: - Lifecycle

    func startListening() {
        guard !isListening else { return }
        isListening = true

        listenQueue.async { [weak self] in
            self?.setupSocket()
        }

        // Stale detection timer + pending approval cleanup
        DispatchQueue.main.async { [weak self] in
            self?.staleTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                self?.checkForStaleSessions()
                self?.cleanupDeadApprovals()
            }
        }

        print("[NARC] 🔌 ClaudeSessionService: listening on \(socketPath)")
    }

    func stopListening() {
        isListening = false
        staleTimer?.invalidate()
        staleTimer = nil
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(socketPath)
    }

    // MARK: - Socket Setup

    private func setupSocket() {
        unlink(socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("[NARC] ❌ ClaudeSessionService: failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let pathBuf = UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self)
                strcpy(pathBuf, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            print("[NARC] ❌ ClaudeSessionService: bind failed: \(String(cString: strerror(errno)))")
            close(serverSocket)
            return
        }

        chmod(socketPath, 0o777)

        guard listen(serverSocket, 10) == 0 else {
            print("[NARC] ❌ ClaudeSessionService: listen failed")
            close(serverSocket)
            return
        }

        print("[NARC] 🔌 Socket ready at \(socketPath)")

        while isListening {
            let clientSocket = accept(serverSocket, nil, nil)
            guard clientSocket >= 0 else { continue }
            handleClient(clientSocket)
        }
    }

    // MARK: - Client Handling

    private func handleClient(_ clientSocket: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = read(clientSocket, &buffer, buffer.count)
        guard bytesRead > 0 else {
            close(clientSocket)
            return
        }

        let data = Data(bytes: buffer, count: bytesRead)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            close(clientSocket)
            return
        }

        let sessionId = json["session_id"] as? String ?? ""
        let event = json["event"] as? String ?? ""
        let status = json["status"] as? String ?? ""
        let tool = json["tool"] as? String
        let toolInput = json["tool_input"] as? [String: Any]
        let cwd = json["cwd"] as? String
        let message = json["message"] as? String
        let tty = json["tty"] as? String
        let narcSessionId = json["narc_session_id"] as? String

        print("[NARC] 🔌 Received: event=\(event) status=\(status) session=\(sessionId.prefix(8))")

        // Build / update session, preserving recentEvents from the previous record
        let previousEvents = self.sessions[sessionId]?.recentEvents ?? []
        let newEvent = ClaudeEvent(
            timestamp: Date(),
            event: event,
            tool: tool,
            summary: Self.summarize(event: event, tool: tool, toolInput: toolInput, message: message)
        )
        var updatedEvents = previousEvents + [newEvent]
        // Trim to keep only the last 12 events per session
        if updatedEvents.count > 12 {
            updatedEvents = Array(updatedEvents.suffix(12))
        }

        let session = ClaudeSession(
            sessionId: sessionId,
            status: ClaudeStatus(rawValue: status) ?? .unknown,
            currentTool: tool,
            toolInput: toolInput,
            cwd: cwd,
            tty: tty,
            narcSessionId: narcSessionId,
            lastUpdated: Date(),
            recentEvents: updatedEvents
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.sessions[sessionId] = session

            if status == "ended" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.sessions.removeValue(forKey: sessionId)
                }
            }
        }

        // Key decision points — trigger attention
        switch event {
        case "PermissionRequest":
            let context = json["context"] as? String
            let approval = PendingApproval(
                sessionId: sessionId,
                narcSessionId: narcSessionId,
                tool: tool ?? "Unknown",
                toolInput: toolInput,
                cwd: cwd,
                context: context,
                tty: tty,
                clientSocket: clientSocket,
                receivedAt: Date()
            )
            DispatchQueue.main.async { [weak self] in
                self?.pendingApprovals.append(approval)
                self?.onAttentionNeeded?(.permissionRequest)
            }
            return  // Keep socket open for response

        case "Stop", "SubagentStop":
            DispatchQueue.main.async { [weak self] in
                let notification = ClaudeNotification(
                    sessionId: sessionId,
                    narcSessionId: narcSessionId,
                    type: .stopped,
                    message: "会话等待输入",
                    cwd: cwd,
                    tty: tty,
                    timestamp: Date()
                )
                self?.notifications.append(notification)
                self?.trimNotifications()
                self?.flashCompleted(sessionId: sessionId)
                self?.onAttentionNeeded?(.stopped(sessionId: sessionId))
            }

        case "StopFailure":
            DispatchQueue.main.async { [weak self] in
                let notification = ClaudeNotification(
                    sessionId: sessionId,
                    narcSessionId: narcSessionId,
                    type: .error,
                    message: message ?? "执行出错",
                    cwd: cwd,
                    tty: tty,
                    timestamp: Date()
                )
                self?.notifications.append(notification)
                self?.trimNotifications()
                self?.flashCompleted(sessionId: sessionId)
                self?.onAttentionNeeded?(.error(sessionId: sessionId, message: message))
            }

        default:
            break
        }

        close(clientSocket)
    }

    // MARK: - Completed Flash

    /// Briefly highlight a session as "just completed" so the workspace banner can show
    /// a "Jump to terminal X" prompt. Auto-clears after `completedFlashDuration`.
    private func flashCompleted(sessionId: String) {
        completedFlash = sessionId
        completedFlashTimer?.invalidate()
        completedFlashTimer = Timer.scheduledTimer(withTimeInterval: completedFlashDuration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.completedFlash = nil
            }
        }
    }

    /// Manually dismiss the completed-flash banner (e.g. user clicked "X" or "Jump").
    func dismissCompletedFlash() {
        completedFlashTimer?.invalidate()
        completedFlashTimer = nil
        completedFlash = nil
    }

    // MARK: - Stale Detection

    private func checkForStaleSessions() {
        let now = Date()
        for (sessionId, session) in sessions {
            if session.status == .runningTool || session.status == .processing {
                if now.timeIntervalSince(session.lastUpdated) > staleThreshold {
                    onAttentionNeeded?(.stale(sessionId: sessionId))
                }
            }
        }
    }

    /// Remove pending approvals whose socket is no longer alive.
    /// This handles the case where user already answered in the CLI terminal —
    /// Claude Code closes the hook process, which closes the socket connection.
    private func cleanupDeadApprovals() {
        var toRemove: [UUID] = []
        for approval in pendingApprovals {
            // Try to check if socket is still connected by peeking
            var buf = [UInt8](repeating: 0, count: 1)
            let result = recv(approval.clientSocket, &buf, 1, MSG_PEEK | MSG_DONTWAIT)
            if result == 0 {
                // Connection closed by peer (user answered in CLI)
                toRemove.append(approval.id)
                close(approval.clientSocket)
            } else if result < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
                // Socket error — also dead
                toRemove.append(approval.id)
                close(approval.clientSocket)
            }
            // If result == -1 with EAGAIN/EWOULDBLOCK, socket is still alive (no data yet)
        }

        if !toRemove.isEmpty {
            pendingApprovals.removeAll { toRemove.contains($0.id) }
            print("[NARC] 🔌 Cleaned up \(toRemove.count) resolved approval(s)")
        }
    }

    // MARK: - Approval Actions

    func approve(_ approval: PendingApproval) {
        respond(to: approval, decision: "allow", reason: "")
    }

    func deny(_ approval: PendingApproval, reason: String = "Denied by user via NARC") {
        respond(to: approval, decision: "deny", reason: reason)
    }

    /// Dismiss an approval without sending a decision — user will handle it in the terminal.
    /// Closes the socket (hook will fall through to CLI's own prompt).
    func dismissApproval(_ approval: PendingApproval) {
        close(approval.clientSocket)
        DispatchQueue.main.async { [weak self] in
            self?.pendingApprovals.removeAll { $0.id == approval.id }
        }
        print("[NARC] 🔌 Dismissed approval for \(approval.tool) — user handling in terminal")
    }

    private func respond(to approval: PendingApproval, decision: String, reason: String) {
        let response: [String: Any] = ["decision": decision, "reason": reason]
        if let data = try? JSONSerialization.data(withJSONObject: response) {
            _ = data.withUnsafeBytes { ptr in
                write(approval.clientSocket, ptr.baseAddress!, data.count)
            }
        }
        close(approval.clientSocket)

        DispatchQueue.main.async { [weak self] in
            self?.pendingApprovals.removeAll { $0.id == approval.id }
        }
        print("[NARC] 🔌 Claude approval: \(decision) for \(approval.tool)")
    }

    // MARK: - Helpers

    func dismissNotification(_ id: UUID) {
        notifications.removeAll { $0.id == id }
    }

    private func trimNotifications() {
        if notifications.count > 20 {
            notifications = Array(notifications.suffix(20))
        }
    }
}

// MARK: - Models

struct ClaudeSession {
    let sessionId: String
    var status: ClaudeStatus
    var currentTool: String?
    var toolInput: [String: Any]?
    var cwd: String?
    var tty: String?          // TTY device path for precise window targeting
    /// When the session was started inside a NARC workspace pane, this carries
    /// the OwnedSession UUID (via the NARC_SESSION_ID env var + narc-hook
    /// reading it). Lets the workspace tab UI find its claude state.
    var narcSessionId: String?
    var lastUpdated: Date
    /// Ring buffer of recent hook events. Capped at 12 entries by the service.
    var recentEvents: [ClaudeEvent] = []

    var statusDescription: String {
        switch status {
        case .waitingForInput: return "等待输入"
        case .processing: return "思考中..."
        case .runningTool:
            if let tool = currentTool { return "执行: \(tool)" }
            return "执行工具中"
        case .waitingForApproval:
            if let tool = currentTool { return "⚠️ 需确认: \(tool)" }
            return "⚠️ 需要确认"
        case .compacting: return "压缩上下文"
        case .ended: return "已结束"
        case .unknown: return "未知"
        }
    }

    var projectName: String? {
        guard let cwd = cwd else { return nil }
        return (cwd as NSString).lastPathComponent
    }
}

enum ClaudeStatus: String {
    case waitingForInput = "waiting_for_input"
    case processing = "processing"
    case runningTool = "running_tool"
    case waitingForApproval = "waiting_for_approval"
    case compacting = "compacting"
    case ended = "ended"
    case unknown = "unknown"
}

struct PendingApproval: Identifiable {
    let id = UUID()
    let sessionId: String
    /// Workspace tab UUID (NARC_SESSION_ID env var) — present when this
    /// approval came from a terminal NARC itself spawned in the Dashboard.
    /// Lets us jump straight to the right tab when the user taps the row.
    let narcSessionId: String?
    let tool: String
    let toolInput: [String: Any]?
    let cwd: String?
    let context: String?  // Claude's recent reasoning from transcript
    let tty: String?      // TTY device path (e.g. "/dev/ttys003") for precise window targeting
    let clientSocket: Int32
    let receivedAt: Date

    /// Short description for compact display
    var commandDescription: String {
        if tool == "Bash", let input = toolInput, let cmd = input["command"] as? String {
            return cmd.count > 80 ? String(cmd.prefix(80)) + "..." : cmd
        }
        if tool == "Edit", let input = toolInput, let path = input["file_path"] as? String {
            return "Edit: \((path as NSString).lastPathComponent)"
        }
        if tool == "Write", let input = toolInput, let path = input["file_path"] as? String {
            return "Write: \((path as NSString).lastPathComponent)"
        }
        return tool
    }

    /// Full command for Bash tools (no truncation)
    var fullCommand: String {
        if tool == "Bash", let input = toolInput, let cmd = input["command"] as? String {
            return cmd
        }
        return commandDescription
    }

    /// File path for Edit/Write tools
    var filePath: String {
        if let input = toolInput, let path = input["file_path"] as? String {
            return path
        }
        return ""
    }

    /// Whether this looks like a high-risk operation
    var isHighRisk: Bool {
        if tool == "Bash", let input = toolInput, let cmd = input["command"] as? String {
            let riskyPatterns = ["rm ", "rm\t", "rmdir", "git push", "git reset --hard",
                                 "drop table", "DROP TABLE", "sudo", "chmod 777",
                                 "format", "> /dev/", "mkfs", "dd if="]
            return riskyPatterns.contains(where: { cmd.contains($0) })
        }
        return false
    }

    var projectName: String {
        return ClaudeProjectName.from(cwd: cwd)
    }

    /// True if this is a tool permission request (Bash/Edit/Write) that can be Allow/Deny'd.
    /// False if it's an interactive question (AskUserQuestion, Elicitation) that needs the user to go answer.
    var isPermissionRequest: Bool {
        let interactiveTools = ["AskUserQuestion", "Elicitation", "SendUserMessage"]
        return !interactiveTools.contains(tool)
    }
}

struct ClaudeNotification: Identifiable {
    let id = UUID()
    let sessionId: String
    /// Workspace tab UUID (NARC_SESSION_ID env var) — same role as on
    /// PendingApproval: lets the panel row jump straight to the matching
    /// tab in the Dashboard.
    let narcSessionId: String?
    let type: NotificationType
    let message: String
    let cwd: String?
    let tty: String?          // TTY device path for precise window targeting
    let timestamp: Date

    enum NotificationType {
        case stopped
        case error
        case stale
    }

    var projectName: String {
        return ClaudeProjectName.from(cwd: cwd)
    }
}

// MARK: - Project name resolver

/// Derives a meaningful "what should we call this Claude session in the UI"
/// label from a raw `cwd`. The naive `lastPathComponent` approach displays
/// the user's home folder as their *username* — i.e. a session running in
/// `/Users/mickmi` shows as "mickmi · 会话等待输入" which looks like
/// nonsense ("who is mickmi? a person? a project?").
///
/// Resolution order:
/// 1. nil cwd → "?"
/// 2. cwd == $HOME → "Home"
/// 3. cwd inside a git repo → repo folder name (the dir that contains .git)
/// 4. cwd looks like ~/<segment>/<rest> → second-to-last segment for context
/// 5. fallback → cwd's last path component
enum ClaudeProjectName {
    static func from(cwd: String?) -> String {
        guard let cwd = cwd, !cwd.isEmpty else { return "?" }

        let home = NSHomeDirectory()
        if cwd == home { return "Home" }

        if let repoName = gitRepoName(startingAt: cwd) {
            return repoName
        }

        let last = (cwd as NSString).lastPathComponent
        // Final fallback: last segment of the path.
        return last.isEmpty ? cwd : last
    }

    /// Walk up from `path` looking for a `.git` directory; if found return
    /// the *containing* directory's name. Capped at 8 hops so a misconfigured
    /// path doesn't traverse the whole disk.
    private static func gitRepoName(startingAt path: String) -> String? {
        var current = (path as NSString).standardizingPath
        let fm = FileManager.default
        for _ in 0..<8 {
            let gitPath = (current as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: gitPath, isDirectory: &isDir) {
                return (current as NSString).lastPathComponent
            }
            let parent = (current as NSString).deletingLastPathComponent
            // Reached root
            if parent == current || parent.isEmpty || parent == "/" { return nil }
            current = parent
        }
        return nil
    }
}

// MARK: - Event Buffer

/// One row in a session's recent-events ring buffer. Used by the workspace
/// detail view to show "what just happened" timeline.
struct ClaudeEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let event: String       // raw hook event name (PreToolUse, Stop, ...)
    let tool: String?       // tool name if applicable
    let summary: String     // human-friendly one-line summary
}

extension ClaudeSessionService {

    /// Build a short, human-friendly description of an incoming hook event for
    /// display in the timeline.
    static func summarize(
        event: String,
        tool: String?,
        toolInput: [String: Any]?,
        message: String?
    ) -> String {
        switch event {
        case "PreToolUse":
            return shortToolDescription(tool: tool, input: toolInput, prefix: "→ ")
        case "PostToolUse":
            return shortToolDescription(tool: tool, input: toolInput, prefix: "✓ ")
        case "PermissionRequest":
            return "⚠️ approval: \(shortToolDescription(tool: tool, input: toolInput, prefix: ""))"
        case "UserPromptSubmit":
            return "💬 user prompt"
        case "Stop", "SubagentStop":
            return "⏸ idle / waiting for input"
        case "StopFailure":
            return "❌ \(message ?? "error")"
        case "PreCompact":
            return "🗜 compacting context"
        case "Notification":
            return "🔔 \(message ?? "notification")"
        case "SessionStart":
            return "▶︎ session start"
        case "SessionEnd":
            return "■ session end"
        default:
            return event
        }
    }

    private static func shortToolDescription(tool: String?, input: [String: Any]?, prefix: String) -> String {
        guard let tool = tool else { return prefix + "tool" }
        if tool == "Bash", let cmd = input?["command"] as? String {
            let trimmed = cmd.count > 60 ? String(cmd.prefix(60)) + "…" : cmd
            return "\(prefix)Bash: \(trimmed)"
        }
        if (tool == "Edit" || tool == "Write" || tool == "Read"),
           let path = input?["file_path"] as? String {
            return "\(prefix)\(tool): \((path as NSString).lastPathComponent)"
        }
        return prefix + tool
    }
}
