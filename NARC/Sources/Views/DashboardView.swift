import SwiftUI

/// Dashboard with embedded multi-terminal workspace.
/// - Top toolbar: new-terminal menu (Shell / Claude).
/// - Left column: list of in-NARC terminal sessions (each is its own PTY+child).
/// - Right column: live, interactive terminal of the selected session.
///
/// Sessions are kept alive by rendering all panes in a ZStack; only the selected
/// one is visible/interactive. ClaudeService is kept around for future status
/// badge enrichment but not used by the MVP.
struct DashboardView: View {
    @ObservedObject var claudeService: ClaudeSessionService
    @StateObject private var terminals = TerminalSessionManager()

    @State private var selectedSessionId: UUID?

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
            if selectedSessionId == nil || !terminals.sessions.contains(where: { $0.id == selectedSessionId }) {
                selectedSessionId = terminals.sessions.last?.id
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

    // MARK: - Left Column (Tab list)

    private var leftColumn: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(terminals.sessions) { session in
                    TerminalTabRow(
                        session: session,
                        isSelected: session.id == selectedSessionId,
                        onTap: { selectedSessionId = session.id },
                        onClose: { terminals.remove(session.id) },
                        onRename: { newTitle in terminals.rename(id: session.id, title: newTitle) }
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
                        isSelected: session.id == selectedSessionId,
                        onExit: { _ in terminals.markDead(session.id) },
                        onTitleChange: { title in terminals.updateAutoTitle(id: session.id, title: title) },
                        onCwdChange: { cwd in terminals.updateCwd(id: session.id, cwd: cwd) }
                    )
                    .opacity(session.id == selectedSessionId ? 1 : 0)
                    .allowsHitTesting(session.id == selectedSessionId)
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
        selectedSessionId = id
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
    var onTap: () -> Void
    var onClose: () -> Void
    var onRename: (String) -> Void

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: NarcSpacing.sm) {
            // Status dot — claude state if known, else alive/dead.
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                titleLine
                metaLine
                if let claudeBadge = claudeBadge {
                    claudeBadge
                }
            }

            Spacer(minLength: 0)

            if isHovering && !isEditing {
                actionButtons
            }
        }
        .padding(.horizontal, NarcSpacing.md)
        .padding(.vertical, NarcSpacing.sm)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if !isEditing { onTap() }
        }
    }

    // MARK: - Pieces

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
        switch status {
        case .processing:           return "⏳"
        case .runningTool:          return "→"
        case .waitingForApproval:   return "⚠️"
        case .waitingForInput:      return "💬"
        case .compacting:           return "🗜"
        case .ended:                return "■"
        case .unknown:              return "·"
        }
    }

    private func claudeBadgeText(_ claude: ClaudeSession) -> String {
        switch claude.status {
        case .processing:
            return "思考中"
        case .runningTool:
            if let tool = claude.currentTool { return tool }
            return "运行工具"
        case .waitingForApproval:
            if let tool = claude.currentTool { return "待审批: \(tool)" }
            return "待审批"
        case .waitingForInput:
            return "等待输入"
        case .compacting:
            return "压缩上下文"
        case .ended:
            return "已结束"
        case .unknown:
            return "—"
        }
    }

    private func claudeBadgeColor(_ status: ClaudeStatus) -> Color {
        switch status {
        case .waitingForApproval:           return .narcDanger
        case .processing, .runningTool:     return .narcAccent
        case .waitingForInput:              return .narcSuccess
        case .compacting:                   return .narcWarn
        case .ended, .unknown:              return .narcTextFaint
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
