import SwiftUI

/// Claude tab content: aggregated multi-session workspace.
/// - Top section: pending approvals (Allow / Deny / Jump inline).
/// - Bottom section: active sessions with status badge + relative time.
/// Tapping any row jumps to the corresponding iTerm/Terminal window.
struct ClaudeSessionListView: View {
    @ObservedObject var claudeService: ClaudeSessionService
    var onClose: () -> Void

    var body: some View {
        let approvals = claudeService.pendingApprovals
        let sessions = activeSessions

        if approvals.isEmpty && sessions.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !approvals.isEmpty {
                        SectionHeader(title: "Pending Approvals", icon: "exclamationmark.triangle.fill")

                        ForEach(approvals) { approval in
                            PendingApprovalRow(
                                approval: approval,
                                onAllow: { claudeService.approve(approval) },
                                onDeny: { claudeService.deny(approval) },
                                onJump: {
                                    claudeService.dismissApproval(approval)
                                    TerminalJumper.jump(
                                        tty: approval.tty,
                                        cwd: approval.cwd,
                                        projectName: approval.projectName
                                    )
                                    onClose()
                                }
                            )
                            if approval.id != approvals.last?.id {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }

                    if !sessions.isEmpty {
                        if !approvals.isEmpty {
                            Divider().padding(.vertical, 4)
                        }
                        SectionHeader(title: "Active Sessions", icon: "terminal.fill")

                        ForEach(sessions, id: \.sessionId) { session in
                            ClaudeSessionRow(
                                session: session,
                                onTap: {
                                    TerminalJumper.jump(
                                        tty: session.tty,
                                        cwd: session.cwd,
                                        projectName: session.projectName
                                    )
                                    onClose()
                                }
                            )
                            if session.sessionId != sessions.last?.sessionId {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Sessions sorted by last activity, with ended sessions hidden.
    private var activeSessions: [ClaudeSession] {
        claudeService.sessions.values
            .filter { $0.status != .ended }
            .sorted { $0.lastUpdated > $1.lastUpdated }
    }

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
}

// MARK: - Pending Approval Row

/// Compact row for an unresolved PermissionRequest. Inline Allow/Deny + Jump-to-terminal.
struct PendingApprovalRow: View {
    let approval: PendingApproval
    var onAllow: () -> Void
    var onDeny: () -> Void
    var onJump: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: NarcSpacing.md) {
            // Risk icon
            Image(systemName: approval.isHighRisk ? "exclamationmark.octagon.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(approval.isHighRisk ? Color.narcDanger : Color.narcWarn)
                .frame(width: 28)

            // Info
            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                HStack(spacing: NarcSpacing.xs) {
                    Text(approval.projectName)
                        .font(.narcSubtitle)
                        .foregroundStyle(Color.narcText)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(Color.narcTextMuted)
                    Text(approval.tool)
                        .font(.narcCaption)
                        .foregroundStyle(Color.narcWarn)
                }
                Text(approval.commandDescription)
                    .font(.narcMonoSmall)
                    .foregroundStyle(Color.narcTextMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            // Action buttons
            HStack(spacing: NarcSpacing.xs) {
                if approval.isPermissionRequest {
                    Button(action: onAllow) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.narcSuccess)
                    }
                    .buttonStyle(.plain)
                    .help("Allow")

                    Button(action: onDeny) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.narcDanger)
                    }
                    .buttonStyle(.plain)
                    .help("Deny")
                }

                Button(action: onJump) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.narcAccent)
                }
                .buttonStyle(.plain)
                .help("Jump to terminal")
            }
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .background(
            isHovering
                ? Color.narcSurfaceMuted
                : (approval.isHighRisk ? Color.narcDanger.opacity(0.08) : Color.narcWarn.opacity(0.06))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

// MARK: - Claude Session Row

/// Row for an active Claude session — status colour-coded, click to jump.
struct ClaudeSessionRow: View {
    let session: ClaudeSession
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: NarcSpacing.md) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .frame(width: 28)

            // Info
            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text(session.projectName ?? "Unknown")
                    .font(.narcSubtitle)
                    .foregroundStyle(Color.narcText)
                    .lineLimit(1)

                HStack(spacing: NarcSpacing.xs) {
                    Text(session.statusDescription)
                        .font(.narcCaption)
                        .foregroundStyle(statusColor)
                    Text("·")
                        .foregroundStyle(Color.narcTextMuted)
                    Text(relativeTime)
                        .font(.narcCaption)
                        .foregroundStyle(Color.narcTextMuted)
                }
            }

            Spacer()

            if isHovering {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcAccent)
            }
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .background(isHovering ? Color.narcSurfaceMuted : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
    }

    private var statusColor: Color {
        switch session.status {
        case .waitingForApproval:
            return .narcDanger
        case .runningTool, .processing:
            return .narcAccent
        case .waitingForInput:
            return .narcSuccess
        case .compacting:
            return .narcWarn
        case .ended, .unknown:
            return .narcTextFaint
        }
    }

    private var relativeTime: String {
        let interval = Date().timeIntervalSince(session.lastUpdated)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}
