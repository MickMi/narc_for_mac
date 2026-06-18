import SwiftUI
import AppKit

// MARK: - Controller

final class SmartCopyBubbleController {
    let view: NSView
    private let onCopy: () -> Void
    private let model = SmartCopyBubbleModel()

    init(onCopy: @escaping () -> Void) {
        self.onCopy = onCopy
        let host = NSHostingView(rootView: SmartCopyBubbleView(model: model, onTap: onCopy))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        host.frame = CGRect(x: 0, y: 0, width: 132, height: 30)
        self.view = host
    }

    /// Position bubble above-right of point, clamped into container bounds (6pt margin).
    func position(near point: CGPoint, in container: CGRect) {
        var x = point.x + 8
        var y = point.y + 8
        x = min(max(6, x), container.maxX - view.frame.width - 6)
        y = min(max(6, y), container.maxY - view.frame.height - 6)
        view.setFrameOrigin(CGPoint(x: x, y: y))
    }

    /// Copy success feedback: switch to "已复制", auto-dismiss after ~1s.
    func showCopied() {
        model.copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.view.removeFromSuperview()
        }
    }
}

// MARK: - Model

final class SmartCopyBubbleModel: ObservableObject {
    @Published var copied = false
}

// MARK: - SwiftUI View

struct SmartCopyBubbleView: View {
    @ObservedObject var model: SmartCopyBubbleModel
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: NarcSpacing.xs) {
                Image(systemName: model.copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                Text(model.copied ? "已复制" : "智能复制")
                    .font(.narcCaption)
                Text("⌘⇧C")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, NarcSpacing.sm)
            .padding(.vertical, NarcSpacing.xs)
            .background(Capsule().fill(model.copied ? Color.narcSuccess : Color.narcAccent))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}
