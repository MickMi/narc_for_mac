import SwiftUI

/// Floating approval panel that shows pending Claude Code permission requests.
/// Appears as a strong visual indicator — always-on-top, near the NARC widget.
struct ClaudeApprovalView: View {
    @ObservedObject var service: ClaudeSessionService

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                Text("Claude Code 权限确认")
                    .font(.headline)
                Spacer()
                Text("\(service.pendingApprovals.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Approval list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(service.pendingApprovals) { approval in
                        ApprovalCard(approval: approval, service: service)
                    }
                }
                .padding(12)
            }

            // Batch actions
            if service.pendingApprovals.count > 1 {
                Divider()
                HStack {
                    Button("全部允许") {
                        let approvals = service.pendingApprovals
                        for a in approvals { service.approve(a) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button("全部拒绝") {
                        let approvals = service.pendingApprovals
                        for a in approvals { service.deny(a) }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(12)
            }
        }
        .frame(width: 360, height: 300)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
}

/// Individual approval card — compact by default, expandable for details
struct ApprovalCard: View {
    let approval: PendingApproval
    let service: ClaudeSessionService
    @State private var isExpanded = false
    @State private var intentSummary: String? = nil
    @State private var isLoadingIntent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: tool icon + type + project + time
            HStack {
                toolIcon
                Text(approval.tool)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(toolColor)
                Text("·")
                    .foregroundColor(.secondary)
                Text(approval.projectName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(timeAgo(approval.receivedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // One-line summary (always visible)
            Text(approval.commandDescription)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .foregroundColor(.primary)

            // Risk indicator
            if approval.isHighRisk {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text("高风险操作")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            // Expanded section: context + full details
            if isExpanded {
                Divider()

                // Show conversation context from transcript (Claude's reasoning)
                if let context = approval.context {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "bubble.left.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text(context.suffix(300))
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(6)
                    }
                    .padding(6)
                    .background(Color.blue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if let intent = intentSummary {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text(intent)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    .padding(6)
                    .background(Color.yellow.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if isLoadingIntent {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("分析意图中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Full command/content
                Text(approval.fullCommand)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Actions
            HStack(spacing: 8) {
                // Primary action: jump to the terminal to answer
                Button(action: { jumpToSession(approval) }) {
                    Label("前往回答", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)

                // Quick approve (for simple permission requests)
                if approval.isPermissionRequest {
                    Button(action: { service.approve(approval) }) {
                        Label("Allow", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .controlSize(.small)

                    Button(action: { service.deny(approval) }) {
                        Label("Deny", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }

                Spacer()

                // Expand/collapse button
                Button(action: { toggleExpand() }) {
                    Label(isExpanded ? "收起" : "详情",
                          systemImage: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "刚刚" }
        if seconds < 60 { return "\(seconds)秒前" }
        return "\(seconds / 60)分钟前"
    }

    private func toggleExpand() {
        isExpanded.toggle()
        // Only call Haiku if expanded, no transcript context available, and not already loaded
        if isExpanded && approval.context == nil && intentSummary == nil && !isLoadingIntent {
            loadIntent()
        }
    }

    /// Jump to the terminal window running this Claude Code session.
    /// Uses TTY device path to precisely target the correct window/tab.
    private func jumpToSession(_ approval: PendingApproval) {
        // Remove this approval from the list (user is going to handle it in terminal)
        service.dismissApproval(approval)

        guard let tty = approval.tty, !tty.isEmpty else {
            // No TTY info — fallback to just activating terminal app
            activateAnyTerminal()
            return
        }

        // Detect which terminal app is running and use TTY-based targeting
        if let _ = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first {
            jumpToTerminalWindow(tty: tty)
        } else if let _ = NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first {
            jumpToITermWindow(tty: tty)
        } else {
            // Other terminals — fallback
            activateAnyTerminal()
        }
    }

    /// Use AppleScript to find and activate the Terminal.app window/tab with a specific TTY
    private func jumpToTerminalWindow(tty: String) {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return
                    end if
                end repeat
            end repeat
            -- Fallback: just activate
            activate
        end tell
        """
        runAppleScript(script)
    }

    /// Use AppleScript to find and activate the iTerm2 session with a specific TTY
    private func jumpToITermWindow(tty: String) {
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select s
                            select t
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
            -- Fallback: just activate
            activate
        end tell
        """
        runAppleScript(script)
    }

    /// Fallback: activate any running terminal app
    private func activateAnyTerminal() {
        let terminalApps = ["com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
        for bundleID in terminalApps {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate()
                print("[NARC] 🔌 Jumped to terminal (no TTY): \(bundleID)")
                return
            }
        }
    }

    /// Run an AppleScript asynchronously
    private func runAppleScript(_ script: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    print("[NARC] 🔌 Jumped to terminal window via TTY")
                } else {
                    let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? ""
                    print("[NARC] ⚠️ AppleScript jump error: \(errStr)")
                }
            } catch {
                print("[NARC] ⚠️ Failed to run osascript: \(error)")
            }
        }
    }

    private func loadIntent() {
        isLoadingIntent = true
        let command = approval.fullCommand
        let tool = approval.tool
        let project = approval.projectName

        DispatchQueue.global(qos: .userInitiated).async {
            // Use claude -p with haiku to quickly summarize intent
            let prompt = "用一句中文简短说明这个操作的意图（不超过30字）。工具: \(tool), 项目: \(project), 内容: \(command.prefix(200))"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/claude")
            process.arguments = ["-p", "--model", "haiku", "--no-session-persistence", prompt]
            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                DispatchQueue.main.async {
                    intentSummary = result.isEmpty ? "无法获取意图" : result
                    isLoadingIntent = false
                }
            } catch {
                DispatchQueue.main.async {
                    intentSummary = "获取意图失败"
                    isLoadingIntent = false
                }
            }
        }
    }

    private var toolIcon: some View {
        Group {
            switch approval.tool {
            case "Bash":
                Image(systemName: "terminal")
                    .foregroundColor(.orange)
            case "Edit":
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            case "Write":
                Image(systemName: "doc.badge.plus")
                    .foregroundColor(.purple)
            default:
                Image(systemName: "gearshape")
                    .foregroundColor(.gray)
            }
        }
        .font(.caption)
    }

    private var toolColor: Color {
        switch approval.tool {
        case "Bash": return .orange
        case "Edit": return .blue
        case "Write": return .purple
        default: return .secondary
        }
    }
}

/// Status indicator for active Claude sessions (for NARC panel integration)
struct ClaudeStatusView: View {
    @ObservedObject var service: ClaudeSessionService

    var body: some View {
        if service.sessions.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(service.sessions.values), id: \.sessionId) { session in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor(session.status))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.projectName ?? "Claude Code")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(session.statusDescription)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        )
    }

    private func statusColor(_ status: ClaudeStatus) -> Color {
        switch status {
        case .waitingForInput: return .green
        case .processing: return .blue
        case .runningTool: return .orange
        case .waitingForApproval: return .red
        case .compacting: return .purple
        case .ended: return .gray
        case .unknown: return .gray
        }
    }
}
