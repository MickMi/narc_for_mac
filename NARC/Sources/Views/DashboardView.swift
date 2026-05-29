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
        .onChange(of: terminals.sessions.map(\.id)) { _ in
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

            Menu {
                Button("Shell (zsh)") { spawnShell() }
                Button("Claude") { spawnClaude() }
            } label: {
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
            .menuStyle(.borderlessButton)
            .fixedSize()
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
                        onClose: { terminals.remove(session.id) }
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
                        onExit: { _ in terminals.markDead(session.id) },
                        onTitleChange: { title in terminals.updateTitle(id: session.id, title: title) }
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
            HStack(spacing: NarcSpacing.sm) {
                Button("+ Shell") { spawnShell() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, NarcSpacing.md)
                    .padding(.vertical, NarcSpacing.xs + 2)
                    .background(Capsule().fill(Color.narcSurfaceMuted))
                Button("+ Claude") { spawnClaude() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, NarcSpacing.md)
                    .padding(.vertical, NarcSpacing.xs + 2)
                    .background(Capsule().fill(Color.narcAccent))
            }
            .font(.narcCaption)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.narcBackground)
    }

    // MARK: - Spawn helpers

    private func spawnShell() {
        let cwd = NSHomeDirectory()
        let id = terminals.newSession(cwd: cwd)
        selectedSessionId = id
    }

    private func spawnClaude() {
        let cwd = NSHomeDirectory()
        let id = terminals.newClaudeSession(cwd: cwd)
        selectedSessionId = id
    }
}

// MARK: - Tab Row

struct TerminalTabRow: View {
    let session: OwnedSession
    let isSelected: Bool
    var onTap: () -> Void
    var onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: NarcSpacing.sm) {
            Circle()
                .fill(session.isAlive ? Color.narcSuccess : Color.narcTextFaint)
                .frame(width: 8, height: 8)
            Text(session.displayTitle)
                .font(.narcCaption)
                .foregroundStyle(session.isAlive ? Color.narcText : Color.narcTextMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.narcTextMuted)
                }
                .buttonStyle(.plain)
                .help("关闭终端")
            }
        }
        .padding(.horizontal, NarcSpacing.md)
        .padding(.vertical, NarcSpacing.xs + 2)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
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
}
