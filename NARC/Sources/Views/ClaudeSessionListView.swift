import SwiftUI

/// Claude tab content: left-right workspace.
/// - Left column: session tabs (status dot + project name).
/// - Right column: detail of the selected session — status, recent events, jump button,
///   inline Allow/Deny if there's a pending approval for this session.
/// - Top banner: when a session emits Stop/StopFailure, briefly show "task done" prompt.
struct ClaudeSessionListView: View {
    @ObservedObject var claudeService: ClaudeSessionService
    var onClose: () -> Void

    /// sessionId currently shown in the right pane. nil → auto-pick first.
    @State private var selectedSessionId: String?

    var body: some View {
        let sessions = activeSessions

        if sessions.isEmpty && claudeService.pendingApprovals.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
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
                            onClose()
                        },
                        onSelect: {
                            selectedSessionId = flashId
                            claudeService.dismissCompletedFlash()
                        },
                        onDismiss: { claudeService.dismissCompletedFlash() }
                    )
                }

                // Body: split
                HStack(spacing: 0) {
                    // Left column: session tabs
                    leftColumn(sessions: sessions)
                        .frame(width: 124)
                        .background(Color.narcBackground.opacity(0.4))

                    Divider()

                    // Right column: detail of selected session
                    rightColumn(sessions: sessions)
                        .frame(maxWidth: .infinity)
                }
            }
            .onAppear {
                ensureValidSelection(sessions: sessions)
            }
            .onChange(of: sessions.map(\.sessionId)) { _, _ in
                ensureValidSelection(sessions: sessions)
            }
        }
    }

    // MARK: - Left Column

    private func leftColumn(sessions: [ClaudeSession]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sessions, id: \.sessionId) { session in
                    SessionTab(
                        session: session,
                        hasPendingApproval: hasPendingApproval(session.sessionId),
                        isSelected: session.sessionId == selectedSessionId,
                        onTap: { selectedSessionId = session.sessionId }
                    )
                    Divider().padding(.leading, 12)
                }
            }
            .padding(.vertical, 4)
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
                    onClose()
                },
                onAllow: { approval in
                    claudeService.approve(approval)
                },
                onDeny: { approval in
                    claudeService.deny(approval)
                }
            )
        } else {
            VStack {
                Spacer()
                Text("Select a session")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: NarcSpacing.md) {
            Spacer()
            Image(systemName: "moon.zzz")
                .font(.system(size: 36))
                .foregroundStyle(Color.narcTextMuted)
            Text("No active Claude sessions")
                .font(.narcSubtitle)
                .foregroundStyle(Color.narcText)
            Text("Start `claude` in any terminal to see it here")
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// Sessions sorted by start order (lastUpdated as a proxy when no fixed order).
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

    /// Make sure we have a valid selection: prefer the existing one if still present;
    /// otherwise pick the session with a pending approval, or the first active one.
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

// MARK: - Completed Banner

/// Top banner shown briefly when a session reaches Stop/StopFailure.
/// Three actions: jump to that terminal, just open the session in this panel, dismiss.
struct CompletedBanner: View {
    let session: ClaudeSession
    var onJump: () -> Void
    var onSelect: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.narcSuccess)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(session.projectName ?? "Session") 已完成")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcText)
                Text("点击切到该会话或跳转到终端")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextMuted)
            }

            Spacer()

            Button("打开", action: onSelect)
                .buttonStyle(.plain)
                .font(.narcCaption)
                .foregroundStyle(Color.narcAccent)

            Button(action: onJump) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .foregroundStyle(Color.narcAccent)
            }
            .buttonStyle(.plain)
            .help("Jump to terminal")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NarcSpacing.md)
        .padding(.vertical, NarcSpacing.sm)
        .background(Color.narcSuccess.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.narcSuccess.opacity(0.25)),
            alignment: .bottom
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Session Tab (Left Column Row)

struct SessionTab: View {
    let session: ClaudeSession
    let hasPendingApproval: Bool
    let isSelected: Bool
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: NarcSpacing.xs) {
            // Status dot
            ZStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                if hasPendingApproval {
                    // Pulse ring for pending approvals
                    Circle()
                        .strokeBorder(Color.narcDanger, lineWidth: 2)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.projectName ?? "Unknown")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(session.statusDescription)
                    .font(.system(size: 9))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, NarcSpacing.sm)
        .padding(.vertical, NarcSpacing.xs + 2)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
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

// MARK: - Session Detail (Right Column)

struct SessionDetailView: View {
    let session: ClaudeSession
    let pendingApproval: PendingApproval?
    var onJump: () -> Void
    var onAllow: (PendingApproval) -> Void
    var onDeny: (PendingApproval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.sm) {
            // Header
            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                HStack(spacing: NarcSpacing.xs) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(session.projectName ?? "Unknown")
                        .font(.narcSubtitle)
                        .foregroundStyle(Color.narcText)
                        .lineLimit(1)
                }

                Text(session.statusDescription)
                    .font(.narcCaption)
                    .foregroundStyle(statusColor)

                if let cwd = session.cwd {
                    Text(cwd)
                        .font(.narcMonoTiny)
                        .foregroundStyle(Color.narcTextMuted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.horizontal, NarcSpacing.md)
            .padding(.top, NarcSpacing.sm)

            Divider().padding(.horizontal, NarcSpacing.sm)

            // Pending approval inline (high priority)
            if let approval = pendingApproval {
                approvalCard(approval)
                    .padding(.horizontal, NarcSpacing.md)
            }

            // Recent events timeline
            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text("最近事件")
                    .font(.narcMonoTiny)
                    .foregroundStyle(Color.narcTextMuted)
                    .padding(.horizontal, NarcSpacing.md)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(session.recentEvents.reversed()) { event in
                            EventRow(event: event)
                        }
                    }
                    .padding(.horizontal, NarcSpacing.md)
                }
                .frame(maxHeight: .infinity)
            }

            // Footer: jump button
            HStack {
                Spacer()
                Button(action: onJump) {
                    HStack(spacing: NarcSpacing.xs) {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text("Jump to terminal")
                            .font(.narcCaption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, NarcSpacing.md)
                    .padding(.vertical, NarcSpacing.xs + 2)
                    .background(
                        Capsule().fill(Color.narcAccent)
                    )
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.bottom, NarcSpacing.sm)
        }
    }

    @ViewBuilder
    private func approvalCard(_ approval: PendingApproval) -> some View {
        VStack(alignment: .leading, spacing: NarcSpacing.xs) {
            HStack(spacing: NarcSpacing.xs) {
                Image(systemName: approval.isHighRisk ? "exclamationmark.octagon.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(approval.isHighRisk ? Color.narcDanger : Color.narcWarn)
                Text("需要审批: \(approval.tool)")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcText)
            }
            Text(approval.commandDescription)
                .font(.narcMonoTiny)
                .foregroundStyle(Color.narcTextMuted)
                .lineLimit(2)

            if approval.isPermissionRequest {
                HStack(spacing: NarcSpacing.xs) {
                    Button(action: { onAllow(approval) }) {
                        Text("Allow")
                            .font(.narcCaption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, NarcSpacing.sm)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.narcSuccess))
                    }
                    .buttonStyle(.plain)
                    Button(action: { onDeny(approval) }) {
                        Text("Deny")
                            .font(.narcCaption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, NarcSpacing.sm)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.narcDanger))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(NarcSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: NarcRadius.sm)
                .fill((approval.isHighRisk ? Color.narcDanger : Color.narcWarn).opacity(0.1))
        )
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
}

// MARK: - Event Row

struct EventRow: View {
    let event: ClaudeEvent

    var body: some View {
        HStack(alignment: .top, spacing: NarcSpacing.xs) {
            Text(timeString)
                .font(.narcMonoTiny)
                .foregroundStyle(Color.narcTextFaint)
                .frame(width: 36, alignment: .leading)
            Text(event.summary)
                .font(.narcMonoTiny)
                .foregroundStyle(Color.narcTextMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: event.timestamp)
    }
}
