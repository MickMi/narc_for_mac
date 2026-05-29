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
                        isSelected: session.id == selectedSessionId,
                        onExit: { _ in terminals.markDead(session.id) },
                        onTitleChange: { title in terminals.updateAutoTitle(id: session.id, title: title) },
                        onCwdChange: { cwd in terminals.updateCwd(id: session.id, cwd: cwd) }
                    )
                    .opacity(session.id == selectedSessionId ? 1 : 0)
                    .allowsHitTesting(session.id == selectedSessionId)
                }
            }
            .background(Color.black)
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
            // Status dot
            Circle()
                .fill(session.isAlive ? Color.narcSuccess : Color.narcTextFaint)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                titleLine
                metaLine
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
        if isSelected {
            Color.narcAccent.opacity(0.18)
        } else if isHovering {
            Color.narcSurfaceMuted
        } else {
            Color.clear
        }
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
