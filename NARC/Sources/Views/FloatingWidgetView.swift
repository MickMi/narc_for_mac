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
            // Background circle — frosted glass material
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: NarcSize.widgetDiameter, height: NarcSize.widgetDiameter)
                .scaleEffect(isHovering ? 1.08 : 1.0)
                .animation(.narcEase, value: isHovering)
                .breathingHalo(active: hasClaudePending || appMonitor.totalBadgeCount > 0)

            // Signal logo
            NarcSignalLogo(animated: true)

            // Badge (accent capsule + count) for IM notifications
            if appMonitor.totalBadgeCount > 0 {
                BadgeView(count: appMonitor.totalBadgeCount)
                    .offset(x: 14, y: -14)
                    .transition(.scale.combined(with: .opacity))
            }

            // Claude pending indicator (small warn dot, bottom-right)
            if hasClaudePending && appMonitor.totalBadgeCount == 0 {
                Circle()
                    .fill(Color.narcWarn)
                    .frame(width: NarcSize.statusDotLarge, height: NarcSize.statusDotLarge)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 1)
                    )
                    .offset(x: 16, y: 16)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: NarcSize.widgetDiameter, height: NarcSize.widgetDiameter)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}

/// Accent notification badge with count.
struct BadgeView: View {
    let count: Int

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.narcAccent)
                .frame(width: NarcSize.badgeSize, height: NarcSize.badgeSize)

            Text(count > 99 ? "99+" : "\(count)")
                .font(.narcMonoSmall)
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
        }
    }
}
