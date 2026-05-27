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

        print("[NARC] 🔌 Received: event=\(event) status=\(status) session=\(sessionId.prefix(8))")

        // Update session state
        let session = ClaudeSession(
            sessionId: sessionId,
            status: ClaudeStatus(rawValue: status) ?? .unknown,
            currentTool: tool,
            toolInput: toolInput,
            cwd: cwd,
            tty: tty,
            lastUpdated: Date()
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
                    type: .stopped,
                    message: "会话等待输入",
                    cwd: cwd,
                    tty: tty,
                    timestamp: Date()
                )
                self?.notifications.append(notification)
                self?.trimNotifications()
                self?.onAttentionNeeded?(.stopped(sessionId: sessionId))
            }

        case "StopFailure":
            DispatchQueue.main.async { [weak self] in
                let notification = ClaudeNotification(
                    sessionId: sessionId,
                    type: .error,
                    message: message ?? "执行出错",
                    cwd: cwd,
                    tty: tty,
                    timestamp: Date()
                )
                self?.notifications.append(notification)
                self?.trimNotifications()
                self?.onAttentionNeeded?(.error(sessionId: sessionId, message: message))
            }

        default:
            break
        }

        close(clientSocket)
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
    var lastUpdated: Date

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
        guard let cwd = cwd else { return "?" }
        return (cwd as NSString).lastPathComponent
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
        guard let cwd = cwd else { return "?" }
        return (cwd as NSString).lastPathComponent
    }
}
