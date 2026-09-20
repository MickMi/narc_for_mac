import SwiftUI

enum SelectedTextTodoFeedbackTone {
    case success
    case info
    case warning
    case error

    var color: Color {
        switch self {
        case .success: return .narcSuccess
        case .info: return .narcInfo
        case .warning: return .narcWarn
        case .error: return .narcDanger
        }
    }

    var systemImage: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}

/// Non-content-bearing feedback for selected-text capture.
///
/// The selected text itself is deliberately never rendered here: a screen-
/// level toast can be visible in recordings or on a shared display. Success
/// feedback exposes only the reversible action for the exact Todo UUID.
struct SelectedTextTodoFeedbackView: View {
    let title: String
    let message: String
    let tone: SelectedTextTodoFeedbackTone
    let actionTitle: String?
    let onAction: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: NarcSpacing.md) {
            Image(systemName: tone.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(tone.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text(title)
                    .font(.narcSubtitle)
                    .foregroundColor(.narcText)
                Text(message)
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: NarcSpacing.sm)

            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle")
                    .font(.narcBody)
                    .foregroundColor(.narcTextFaint)
            }
            .buttonStyle(.plain)
            .help("关闭")
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.md)
        .frame(width: 400, height: 76)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NarcRadius.lg, style: .continuous)
                .strokeBorder(tone.color.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: tone.color.opacity(0.14), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }
}
