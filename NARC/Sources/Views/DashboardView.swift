import SwiftUI

/// Dashboard with embedded multi-terminal workspace.
/// - Top toolbar: new-terminal menu (Shell / Claude).
/// - Left column: list of in-NARC terminal sessions (each is its own PTY+child).
/// - Right column: live, interactive terminal of the selected session.
///
/// Sessions are kept alive by rendering all panes in a ZStack; only the selected
/// one is visible/interactive. ClaudeService is kept around for future status
/// badge enrichment but not used by the MVP.
///
/// `terminals` is owned by AppDelegate (not @StateObject here) so closing the
/// Dashboard window doesn't tear it down — child PTYs keep running and the
/// next time the window is summoned we see the same tabs / output / state.
struct DashboardView: View {
    @ObservedObject var claudeService: ClaudeSessionService
    @ObservedObject var terminals: TerminalSessionManager

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                leftColumn
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
                rightColumn
                    .frame(minWidth: 420, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color.narcBackground)
        .onChange(of: terminals.sessions.map(\.id)) { _, _ in
            // Auto-select the first session when none is selected, or pick the
            // newest one if our selection just got removed.
            if terminals.selectedId == nil
                || !terminals.sessions.contains(where: { $0.id == terminals.selectedId }) {
                terminals.selectedId = terminals.sessions.last?.id
            }
        }
        .onAppear {
            // Cold start: if we have sessions but no selection, default to last.
            if terminals.selectedId == nil {
                terminals.selectedId = terminals.sessions.last?.id
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(Color.narcAccent)
            Text("NARC Workspace")
                .font(.narcSubtitle)
                .foregroundStyle(Color.narcText)
            Text("·")
                .foregroundStyle(Color.narcTextMuted)
            Text("\(terminals.sessions.count) 个终端")
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)

            Spacer()

            // Smart-paste hint — keeps the ⌘⇧V shortcut discoverable. Without
            // this strip the feature is invisible (we can't add an item to the
            // Edit menu without going Catalyst-style menu builder).
            smartPasteHint

            Button(action: spawnShell) {
                HStack(spacing: NarcSpacing.xs) {
                    Image(systemName: "plus")
                    Text("新建终端")
                        .font(.narcCaption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, NarcSpacing.md)
                .padding(.vertical, NarcSpacing.xs + 2)
                .background(Capsule().fill(Color.narcAccent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
    }

    /// Permanent affordance reminding the user that ⌘⇧V exists and what it
    /// does. macOS doesn't surface the shortcut anywhere else (we're not using
    /// the Edit menu), so without this hint the feature would be undiscoverable.
    private var smartPasteHint: some View {
        HStack(spacing: NarcSpacing.xs) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 10))
            Text("⌘⇧V")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, NarcSpacing.xs)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: NarcRadius.xs)
                        .fill(Color.narcSurfaceMuted)
                )
            Text("智能粘贴")
                .font(.narcCaption)
        }
        .foregroundStyle(Color.narcTextMuted)
        .help("从 VS Code / Slack 粘贴代码时，⌘⇧V 自动剥掉每行最前面的公共缩进；普通 ⌘V 保持原样不变。")
    }

    // MARK: - Left Column (Tab list)

    private var leftColumn: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(terminals.sessions) { session in
                    // Look up a pending approval whose narc_session_id matches
                    // this tab. Strict match so external (iTerm) approvals
                    // don't accidentally borrow a workspace tab's UI.
                    let pendingApproval = claudeService.pendingApprovals.first {
                        $0.narcSessionId == session.id.uuidString
                    }
                    TerminalTabRow(
                        session: session,
                        isSelected: session.id == terminals.selectedId,
                        approval: pendingApproval,
                        onTap: { terminals.selectedId = session.id },
                        onClose: { terminals.remove(session.id) },
                        onRename: { newTitle in terminals.rename(id: session.id, title: newTitle) },
                        onApproveApproval: pendingApproval.map { ap in
                            { claudeService.approve(ap) }
                        },
                        onDenyApproval: pendingApproval.map { ap in
                            { claudeService.deny(ap) }
                        },
                        onDismissApproval: pendingApproval.map { ap in
                            { claudeService.dismissApproval(ap) }
                        }
                    )
                    Divider().padding(.leading, 12)
                }
            }
            .padding(.vertical, NarcSpacing.xs)
        }
        .background(Color.narcBackground.opacity(0.6))
    }

    // MARK: - Right Column (Active terminal)

    @ViewBuilder
    private var rightColumn: some View {
        if terminals.sessions.isEmpty {
            emptyState
        } else {
            ZStack {
                ForEach(terminals.sessions) { session in
                    TerminalPaneView(
                        executable: session.executable,
                        args: session.args,
                        cwd: session.cwd,
                        narcSessionId: session.id.uuidString,
                        isSelected: session.id == terminals.selectedId,
                        onExit: { _ in terminals.markDead(session.id) },
                        onTitleChange: { title in terminals.updateAutoTitle(id: session.id, title: title) },
                        onCwdChange: { cwd in terminals.updateCwd(id: session.id, cwd: cwd) }
                    )
                    .opacity(session.id == terminals.selectedId ? 1 : 0)
                    .allowsHitTesting(session.id == terminals.selectedId)
                }
            }
            .background(Color.narcBackground)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: NarcSpacing.md) {
            Spacer()
            Image(systemName: "terminal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.narcTextMuted)
            Text("还没有终端")
                .font(.narcSubtitle)
                .foregroundStyle(Color.narcText)
            Text("点击右上角「新建终端」开始")
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)
            Button(action: spawnShell) {
                HStack(spacing: NarcSpacing.xs) {
                    Image(systemName: "plus.circle.fill")
                    Text("新建终端")
                        .font(.narcCaption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, NarcSpacing.lg)
                .padding(.vertical, NarcSpacing.sm)
                .background(Capsule().fill(Color.narcAccent))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.narcBackground)
    }

    // MARK: - Spawn

    private func spawnShell() {
        let cwd = NSHomeDirectory()
        let id = terminals.newSession(cwd: cwd)
        terminals.selectedId = id
    }
}

// MARK: - Tab Row

/// Left-column row for one terminal session. Shows:
/// - status dot (alive/exited)
/// - title (rename via double-click or pencil button)
/// - cwd (auto-tracked via OSC 7, shortened with ~)
/// - hover-revealed pencil + ✕ buttons
struct TerminalTabRow: View {
    let session: OwnedSession
    let isSelected: Bool
    /// When this tab has a pending approval, the approval is threaded in here
    /// so the row can render a ⚠️ button that pops over an inline approval
    /// card (Allow / Deny / handle-in-terminal). nil = no popover button.
    var approval: PendingApproval?
    var onTap: () -> Void
    var onClose: () -> Void
    var onRename: (String) -> Void
    /// Triggered when the user taps Allow inside the popover.
    var onApproveApproval: (() -> Void)?
    /// Triggered when the user taps Deny inside the popover.
    var onDenyApproval: (() -> Void)?
    /// Triggered when the user picks "在终端处理" — closes the popover and
    /// hands control back to the CLI prompt.
    var onDismissApproval: (() -> Void)?

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var attentionPulse = false
    @State private var showApprovalPopover = false
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left attention bar — slim vertical accent for needs-attention
            // tabs. This is the primary "look here" cue per the design
            // decision that the sidebar is the only notification surface.
            attentionBar

            HStack(alignment: .top, spacing: NarcSpacing.sm) {
                // Status dot — claude state if known, else alive/dead.
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 2) {
                    titleLine
                    metaLine
                    claudeBadge
                }

                Spacer(minLength: 0)

                if let approval = approval {
                    // Approval pending → always-visible ⚠️ button so the user
                    // can pop the inline decision card without first hovering.
                    approvalButton(approval: approval)
                } else if isHovering && !isEditing {
                    actionButtons
                } else if session.hasUnseenChange && !isSelected {
                    // Unseen indicator — appears when the claude state
                    // changed while user was on a different tab. Cleared
                    // automatically by TerminalSessionManager.selectedId
                    // when the user switches to this tab.
                    unseenDot
                }
            }
            .padding(.horizontal, NarcSpacing.md)
            .padding(.vertical, NarcSpacing.sm)
        }
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if !isEditing { onTap() }
        }
        .onAppear {
            if needsAttention { attentionPulse.toggle() }
        }
        .onChange(of: needsAttention) { _, nowAttention in
            if nowAttention { attentionPulse.toggle() }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var attentionBar: some View {
        if needsAttention {
            Rectangle()
                .fill(Color.narcDanger)
                .frame(width: 3)
                .opacity(attentionPulse ? 1.0 : 0.4)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: attentionPulse
                )
        } else {
            // Reserve the same 3pt gutter so titles never shift horizontally
            // when a tab toggles between attention / non-attention states.
            Color.clear.frame(width: 3)
        }
    }

    private var unseenDot: some View {
        Circle()
            .fill(Color.narcDanger)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
            )
            .help("此标签页在你离开后状态有变化")
    }

    /// Always-visible ⚠️ button for tabs with a pending approval. Tapping
    /// pops a `ApprovalPopover` anchored to the right edge of the sidebar
    /// so the user can read the full tool / command without leaving the
    /// Workspace and act inline.
    private func approvalButton(approval: PendingApproval) -> some View {
        Button {
            showApprovalPopover.toggle()
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.narcDanger)
        }
        .buttonStyle(.plain)
        .help("查看 / 处理审批")
        .popover(isPresented: $showApprovalPopover, arrowEdge: .trailing) {
            ApprovalPopoverContent(
                approval: approval,
                projectLabel: ClaudeProjectName.from(cwd: approval.cwd),
                onAllow: {
                    showApprovalPopover = false
                    onApproveApproval?()
                },
                onDeny: {
                    showApprovalPopover = false
                    onDenyApproval?()
                },
                onHandleInTerminal: {
                    showApprovalPopover = false
                    onDismissApproval?()
                }
            )
        }
    }

    @ViewBuilder
    private var titleLine: some View {
        if isEditing {
            TextField("Title", text: $editText)
                .textFieldStyle(.plain)
                .font(.narcCaption)
                .foregroundStyle(Color.narcText)
                .focused($titleFieldFocused)
                .onSubmit { commitEdit() }
                .onExitCommand { cancelEdit() }
                .padding(.vertical, 1)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: NarcRadius.xs)
                        .fill(Color.narcSurfaceMuted)
                )
        } else {
            Text(session.displayTitle)
                .font(.narcCaption)
                .fontWeight(.medium)
                .foregroundStyle(session.isAlive ? Color.narcText : Color.narcTextMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .onTapGesture(count: 2) { startEdit() }
        }
    }

    private var metaLine: some View {
        HStack(spacing: NarcSpacing.xs) {
            if let cwd = session.cwd, !cwd.isEmpty {
                Text(shortCwd(cwd))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.narcTextMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            Text(timeAgo(session.creationDate))
                .font(.system(size: 10))
                .foregroundStyle(Color.narcTextFaint)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: NarcSpacing.xs) {
            Button(action: startEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.narcTextMuted)
            }
            .buttonStyle(.plain)
            .help("重命名（双击标题也可以）")

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.narcTextMuted)
            }
            .buttonStyle(.plain)
            .help("关闭终端")
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if needsAttention {
            // Pulse-ish red tint when claude needs the user (approval/error).
            Color.narcDanger.opacity(isSelected ? 0.22 : 0.12)
        } else if isSelected {
            Color.narcAccent.opacity(0.18)
        } else if isHovering {
            Color.narcSurfaceMuted
        } else {
            Color.clear
        }
    }

    /// True when the tab should grab the user's attention (waiting for approval,
    /// recently errored, idle waiting for input). Drives the red row tint.
    private var needsAttention: Bool {
        guard let claude = session.claude else { return false }
        switch claude.status {
        case .waitingForApproval: return true
        default: return false
        }
    }

    /// Optional row showing the live claude state (icon + short label).
    @ViewBuilder
    private var claudeBadge: some View {
        if let claude = session.claude {
            HStack(spacing: NarcSpacing.xs) {
                Text(claudeBadgeIcon(claude.status))
                    .font(.system(size: 10))
                Text(claudeBadgeText(claude))
                    .font(.system(size: 10))
                    .foregroundStyle(claudeBadgeColor(claude.status))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.top, 1)
        }
    }

    private func claudeBadgeIcon(_ status: ClaudeStatus) -> String {
        // 3-bucket model per product decision: processing / waiting-input /
        // waiting-approval. Subtle differentiation inside "processing" via
        // emoji (thinking vs tool vs compacting), but the same color.
        switch status {
        case .processing:           return "⏳"
        case .runningTool:          return "→"
        case .compacting:           return "🗜"
        case .waitingForApproval:   return "⚠️"
        case .waitingForInput:      return "💬"
        case .ended:                return "■"
        case .unknown:              return "·"
        }
    }

    private func claudeBadgeText(_ claude: ClaudeSession) -> String {
        // Subtitle reads as "what is claude doing right now" — gives the
        // user the info they need to decide whether to interrupt.
        switch claude.status {
        case .processing:
            return "思考中"
        case .runningTool:
            // Show the live tool name so the user sees "Bash" / "Edit: foo.swift"
            // rather than a generic "running tool". Falls back to short label
            // if the tool isn't known yet (race between hook events).
            if let tool = claude.currentTool, !tool.isEmpty {
                return Self.shortToolLabel(tool: tool, input: claude.toolInput)
            }
            return "运行工具"
        case .compacting:
            return "压缩上下文"
        case .waitingForApproval:
            if let tool = claude.currentTool { return "待审批: \(tool)" }
            return "待审批"
        case .waitingForInput:
            return "等待输入"
        case .ended:
            return "已结束"
        case .unknown:
            return "—"
        }
    }

    /// Compact one-line description of a running tool. Mirrors what the
    /// Dashboard right-pane scrollback would say.
    private static func shortToolLabel(tool: String, input: [String: Any]?) -> String {
        if tool == "Bash", let cmd = input?["command"] as? String {
            let trimmed = cmd.count > 32 ? String(cmd.prefix(32)) + "…" : cmd
            return "Bash: \(trimmed)"
        }
        if (tool == "Edit" || tool == "Write" || tool == "Read"),
           let path = input?["file_path"] as? String {
            return "\(tool): \((path as NSString).lastPathComponent)"
        }
        return tool
    }

    private func claudeBadgeColor(_ status: ClaudeStatus) -> Color {
        // 3-bucket color model:
        //  - blue  = "claude is working" (processing / runningTool / compacting)
        //  - green = "claude is waiting for you to do something light" (waitingForInput)
        //  - red   = "claude needs explicit decision" (waitingForApproval)
        // ended/unknown are de-emphasized (gray).
        switch status {
        case .waitingForApproval:                            return .narcDanger
        case .processing, .runningTool, .compacting:         return .narcAccent
        case .waitingForInput:                               return .narcSuccess
        case .ended, .unknown:                               return .narcTextFaint
        }
    }

    private var statusDotColor: Color {
        if let claude = session.claude {
            return claudeBadgeColor(claude.status)
        }
        return session.isAlive ? .narcSuccess : .narcTextFaint
    }

    // MARK: - Edit lifecycle

    private func startEdit() {
        editText = session.userTitle ?? session.displayTitle
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            titleFieldFocused = true
        }
    }

    private func commitEdit() {
        onRename(editText)
        isEditing = false
        titleFieldFocused = false
    }

    private func cancelEdit() {
        isEditing = false
        titleFieldFocused = false
    }

    // MARK: - Formatting

    private func shortCwd(_ cwd: String) -> String {
        let home = NSHomeDirectory()
        if cwd == home { return "~" }
        if cwd.hasPrefix(home + "/") { return "~" + cwd.dropFirst(home.count) }
        return cwd
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

// MARK: - Approval Popover

/// Inline approval card popped from a tab's ⚠️ button. Shows the full tool
/// + command/file path, plus three action buttons (Allow / Deny / handle in
/// terminal). All three close the popover via the parent's binding.
///
/// `AskUserQuestion` / `Elicitation` / `SendUserMessage` are interactive
/// tools — Allow/Deny don't apply because the actual prompt happens inside
/// the terminal. For those we collapse to a single "去终端回答" button.
struct ApprovalPopoverContent: View {
    let approval: PendingApproval
    let projectLabel: String
    var onAllow: () -> Void
    var onDeny: () -> Void
    var onHandleInTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.md) {
            header
            commandBlock
            buttonRow
        }
        .padding(NarcSpacing.lg)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: NarcSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.narcDanger)
            VStack(alignment: .leading, spacing: 2) {
                Text("待审批")
                    .font(.narcSubtitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.narcText)
                HStack(spacing: NarcSpacing.xs) {
                    Text(projectLabel)
                        .font(.narcCaption)
                        .foregroundStyle(Color.narcTextMuted)
                    Text("·")
                        .foregroundStyle(Color.narcTextMuted)
                    Text(approval.tool)
                        .font(.narcCaption)
                        .foregroundStyle(Color.narcDanger)
                        .padding(.horizontal, NarcSpacing.xs)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.narcDanger.opacity(0.14))
                        )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var commandBlock: some View {
        ScrollView {
            Text(displayBody)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.narcText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NarcSpacing.sm)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: NarcRadius.sm)
                .fill(Color.narcSurfaceMuted)
        )
    }

    @ViewBuilder
    private var buttonRow: some View {
        if approval.isPermissionRequest {
            HStack(spacing: NarcSpacing.sm) {
                Button(action: onAllow) {
                    Text("允许")
                        .font(.narcCaption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NarcSpacing.sm)
                        .background(Capsule().fill(Color.narcSuccess))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return)

                Button(action: onDeny) {
                    Text("拒绝")
                        .font(.narcCaption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NarcSpacing.sm)
                        .background(Capsule().fill(Color.narcDanger))
                }
                .buttonStyle(.plain)

                Button(action: onHandleInTerminal) {
                    Text("去终端处理")
                        .font(.narcCaption)
                        .foregroundStyle(Color.narcTextMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NarcSpacing.sm)
                        .background(
                            Capsule().strokeBorder(Color.narcBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        } else {
            // Interactive tools (AskUserQuestion / Elicitation / SendUserMessage)
            // — Allow/Deny make no semantic sense, only "go answer in the terminal".
            Button(action: onHandleInTerminal) {
                Text("去终端回答")
                    .font(.narcCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NarcSpacing.sm)
                    .background(Capsule().fill(Color.narcAccent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return)
        }
    }

    private var displayBody: String {
        // Bash → full command. Edit/Write/Read → file path. Everything else
        // → tool input as JSON-ish summary.
        if approval.tool == "Bash", let input = approval.toolInput,
           let cmd = input["command"] as? String {
            return cmd
        }
        if let input = approval.toolInput,
           let path = input["file_path"] as? String {
            return path
        }
        if let input = approval.toolInput {
            return input.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        }
        return approval.commandDescription
    }
}
