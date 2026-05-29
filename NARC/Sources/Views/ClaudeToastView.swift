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
        HStack(spacing: NarcSpacing.md) {
            // Left: status icon
            statusIcon
                .frame(width: 28, height: 28)

            // Middle: info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: NarcSpacing.xs) {
                    Text(event.projectName)
                        .font(.narcBody)
                        .fontWeight(.semibold)
                        .foregroundColor(.narcText)
                    Text("·")
                        .foregroundColor(.narcTextMuted)
                    Text(event.statusLabel)
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)
                }

                Text(event.detail)
                    .font(.narcMonoSmall)
                    .foregroundColor(.narcText.opacity(0.8))
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
                    .buttonStyle(ToastActionButtonStyle(color: .narcSuccess))

                    Button(action: onDeny) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(ToastActionButtonStyle(color: .narcDanger))
                }

                Button(action: onJump) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.narcAccent)
                }
                .buttonStyle(.plain)
                .help("跳转到终端")

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle")
                        .font(.narcBody)
                        .foregroundColor(.narcTextFaint)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .frame(width: NarcSize.toastWidth)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: NarcRadius.lg)
                .strokeBorder(event.type.toneColor.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: event.type.toneColor.opacity(0.15), radius: 18, y: 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch event.type {
        case .permissionRequest:
            ZStack {
                Circle().fill(Color.narcWarn.opacity(0.15))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.narcWarn)
            }
        case .waitingForInput:
            ZStack {
                Circle().fill(Color.narcInfo.opacity(0.15))
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.narcInfo)
            }
        case .error:
            ZStack {
                Circle().fill(Color.narcDanger.opacity(0.15))
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.narcDanger)
            }
        case .stale:
            ZStack {
                Circle().fill(Color.narcWarn.opacity(0.15))
                Image(systemName: "clock.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.narcWarn)
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

        /// Maps each event type to its semantic tone color from design tokens.
        var toneColor: Color {
            switch self {
            case .permissionRequest: return .narcWarn
            case .waitingForInput: return .narcInfo
            case .error: return .narcDanger
            case .stale: return .narcWarn
            }
        }
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
