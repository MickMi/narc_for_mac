import SwiftUI

/// The circular floating widget that sits on the desktop.
struct FloatingWidgetView: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var claudeService: ClaudeSessionService
    var onTap: () -> Void

    @State private var isHovering = false

    /// Whether Claude has pending items (approvals or notifications)
    private var hasClaudePending: Bool {
        !claudeService.pendingApprovals.isEmpty || !claudeService.notifications.isEmpty
    }

    var body: some View {
        ZStack {
            // Background circle — orange tint when Claude needs attention
            Circle()
                .fill(hasClaudePending
                    ? Color.orange.opacity(isHovering ? 1.0 : 0.85)
                    : Color.black.opacity(isHovering ? 1.0 : 0.7))
                .frame(width: 48, height: 48)
                .scaleEffect(isHovering ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .animation(.easeInOut(duration: 0.3), value: hasClaudePending)

            // "N" logo
            Text("N")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            // Badge (red dot + count) for IM notifications
            if appMonitor.totalBadgeCount > 0 {
                BadgeView(count: appMonitor.totalBadgeCount)
                    .offset(x: 14, y: -14)
                    .transition(.scale.combined(with: .opacity))
            }

            // Claude pending indicator (small orange dot, bottom-right)
            if hasClaudePending && appMonitor.totalBadgeCount == 0 {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 1)
                    )
                    .offset(x: 16, y: 16)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 48, height: 48)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}

/// Red notification badge with count.
struct BadgeView: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red)
                .frame(width: 20, height: 20)

            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
        }
    }
}
