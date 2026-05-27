import SwiftUI

/// Lightweight toast notification for Claude Code events.
/// Appears at the top-right of the focused screen, stays until user interacts or event resolves.
struct ClaudeToastView: View {
    let event: ClaudeToastEvent
    var onJump: () -> Void
    var onDismiss: () -> Void
    var onAllow: (() -> Void)? = nil
    var onDeny: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Left: status icon
            statusIcon
                .frame(width: 28, height: 28)

            // Middle: info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(event.projectName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(event.statusLabel)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text(event.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Right: action buttons
            HStack(spacing: 6) {
                if let onAllow = onAllow, let onDeny = onDeny {
                    // Permission request: Allow/Deny + Jump
                    Button(action: onAllow) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(ToastActionButtonStyle(color: .green))

                    Button(action: onDeny) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(ToastActionButtonStyle(color: .red))
                }

                Button(action: onJump) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("跳转到终端")

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 360)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch event.type {
        case .permissionRequest:
            ZStack {
                Circle().fill(Color.orange.opacity(0.15))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
            }
        case .waitingForInput:
            ZStack {
                Circle().fill(Color.blue.opacity(0.15))
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
            }
        case .error:
            ZStack {
                Circle().fill(Color.red.opacity(0.15))
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
        case .stale:
            ZStack {
                Circle().fill(Color.yellow.opacity(0.15))
                Image(systemName: "clock.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.yellow)
            }
        }
    }
}

/// Button style for compact toast action buttons
struct ToastActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .fill(configuration.isPressed ? color.opacity(0.3) : color.opacity(0.15))
            )
            .foregroundColor(color)
    }
}

// MARK: - Toast Event Model

struct ClaudeToastEvent: Identifiable {
    let id = UUID()
    let type: EventType
    let projectName: String
    let detail: String
    let tty: String?
    let cwd: String?           // Full CWD path for fallback window matching
    let sessionId: String
    /// For permission requests, we keep a reference to allow/deny
    var approval: PendingApproval?

    enum EventType {
        case permissionRequest
        case waitingForInput
        case error
        case stale
    }

    var statusLabel: String {
        switch type {
        case .permissionRequest: return "需要确认"
        case .waitingForInput: return "等待输入"
        case .error: return "出错"
        case .stale: return "可能卡住"
        }
    }
}
