import SwiftUI

/// Independent dashboard view — top toolbar (new-terminal button) + completed banner +
/// HSplit (session list / detail). Reuses `SessionDetailView` and `CompletedBanner`
/// from `ClaudeSessionListView.swift`.
struct DashboardView: View {
    @ObservedObject var claudeService: ClaudeSessionService

    @State private var selectedSessionId: String?

    var body: some View {
        let sessions = activeSessions

        VStack(spacing: 0) {
            toolbar(sessionCount: sessions.count)
            Divider()

            // Completed-flash banner
            if let flashId = claudeService.completedFlash,
               let flashSession = claudeService.sessions[flashId] {
                CompletedBanner(
                    session: flashSession,
                    onJump: {
                        TerminalJumper.jump(
                            tty: flashSession.tty,
                            cwd: flashSession.cwd,
                            projectName: flashSession.projectName
                        )
                        claudeService.dismissCompletedFlash()
                    },
                    onSelect: {
                        selectedSessionId = flashId
                        claudeService.dismissCompletedFlash()
                    },
                    onDismiss: { claudeService.dismissCompletedFlash() }
                )
            }

            // Body
            if sessions.isEmpty && claudeService.pendingApprovals.isEmpty {
                emptyState
            } else {
                HSplitView {
                    leftColumn(sessions: sessions)
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                    rightColumn(sessions: sessions)
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 660, minHeight: 420)
        .background(VisualEffectBackground(material: .windowBackground))
        .onAppear { ensureValidSelection(sessions: sessions) }
        .onChange(of: sessions.map(\.sessionId)) { _ in
            ensureValidSelection(sessions: sessions)
        }
    }

    // MARK: - Toolbar

    private func toolbar(sessionCount: Int) -> some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(Color.narcAccent)
            Text("Claude Workspace")
                .font(.narcSubtitle)
                .foregroundStyle(Color.narcText)
            Text("·")
                .foregroundStyle(Color.narcTextMuted)
            Text("\(sessionCount) 个会话")
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)

            Spacer()

            Button(action: { TerminalJumper.spawnClaude() }) {
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

    // MARK: - Left Column

    private func leftColumn(sessions: [ClaudeSession]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sessions, id: \.sessionId) { session in
                    DashboardSessionRow(
                        session: session,
                        hasPendingApproval: hasPendingApproval(session.sessionId),
                        isSelected: session.sessionId == selectedSessionId,
                        onTap: { selectedSessionId = session.sessionId },
                        onClose: { TerminalJumper.closeSession(tty: session.tty) }
                    )
                    Divider().padding(.leading, 14)
                }
            }
            .padding(.vertical, NarcSpacing.xs)
        }
    }

    // MARK: - Right Column

    @ViewBuilder
    private func rightColumn(sessions: [ClaudeSession]) -> some View {
        if let selectedId = selectedSessionId,
           let session = sessions.first(where: { $0.sessionId == selectedId }) {
            SessionDetailView(
                session: session,
                pendingApproval: pendingApprovalFor(selectedId),
                onJump: {
                    TerminalJumper.jump(
                        tty: session.tty,
                        cwd: session.cwd,
                        projectName: session.projectName
                    )
                },
                onAllow: { approval in claudeService.approve(approval) },
                onDeny: { approval in claudeService.deny(approval) }
            )
        } else {
            VStack {
                Spacer()
                Text("选择左侧会话查看详情")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: NarcSpacing.lg) {
            Spacer()
            Image(systemName: "terminal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.narcTextMuted)
            Text("暂无 Claude 会话")
                .font(.narcSubtitle)
                .foregroundStyle(Color.narcText)
            Text("点击右上角「新建终端」开始一个新会话")
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)
            Button(action: { TerminalJumper.spawnClaude() }) {
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
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var activeSessions: [ClaudeSession] {
        claudeService.sessions.values
            .filter { $0.status != .ended }
            .sorted { $0.lastUpdated < $1.lastUpdated }
    }

    private func hasPendingApproval(_ sessionId: String) -> Bool {
        claudeService.pendingApprovals.contains { $0.sessionId == sessionId }
    }

    private func pendingApprovalFor(_ sessionId: String) -> PendingApproval? {
        claudeService.pendingApprovals.first { $0.sessionId == sessionId }
    }

    private func ensureValidSelection(sessions: [ClaudeSession]) {
        if let current = selectedSessionId, sessions.contains(where: { $0.sessionId == current }) {
            return
        }
        if let pending = sessions.first(where: { hasPendingApproval($0.sessionId) }) {
            selectedSessionId = pending.sessionId
            return
        }
        selectedSessionId = sessions.first?.sessionId
    }
}

// MARK: - Dashboard Session Row

/// Wider/heavier session row for the dashboard, with a confirming-close button.
struct DashboardSessionRow: View {
    let session: ClaudeSession
    let hasPendingApproval: Bool
    let isSelected: Bool
    var onTap: () -> Void
    var onClose: () -> Void

    @State private var isHovering = false
    @State private var confirmingClose = false

    var body: some View {
        HStack(spacing: NarcSpacing.sm) {
            // Status dot
            ZStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                if hasPendingApproval {
                    Circle()
                        .strokeBorder(Color.narcDanger, lineWidth: 2)
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName ?? "Unknown")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcText)
                    .lineLimit(1)
                Text(session.statusDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Close button — confirm on first click, execute on second.
            if isHovering || confirmingClose {
                Button(action: handleCloseTap) {
                    Image(systemName: confirmingClose ? "exclamationmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(confirmingClose ? Color.narcDanger : Color.narcTextMuted)
                }
                .buttonStyle(.plain)
                .help(confirmingClose ? "再点一次确认关闭" : "关闭终端")
            }
        }
        .padding(.horizontal, NarcSpacing.md)
        .padding(.vertical, NarcSpacing.xs + 2)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
    }

    private func handleCloseTap() {
        if confirmingClose {
            onClose()
            confirmingClose = false
        } else {
            confirmingClose = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                confirmingClose = false
            }
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .waitingForApproval: return .narcDanger
        case .runningTool, .processing: return .narcAccent
        case .waitingForInput: return .narcSuccess
        case .compacting: return .narcWarn
        case .ended, .unknown: return .narcTextFaint
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.narcAccent.opacity(0.18)
        } else if isHovering {
            Color.narcSurfaceMuted
        } else if hasPendingApproval {
            Color.narcDanger.opacity(0.08)
        } else {
            Color.clear
        }
    }
}
