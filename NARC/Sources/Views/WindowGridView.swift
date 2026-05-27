import SwiftUI

/// Window management tab content: keyboard shortcut reference guide.
/// All operations are performed via hotkeys — this view is informational only.
struct WindowGridView: View {
    @ObservedObject var windowManager: WindowManagerService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Window Shortcuts")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.bottom, 4)

                // Layout shortcuts in compact rows
                ForEach(WindowLayout.allCases) { layout in
                    ShortcutRow(layout: layout)
                }

                Divider()
                    .padding(.vertical, 4)

                // Additional tips
                VStack(alignment: .leading, spacing: 6) {
                    tipRow(icon: "arrow.left.arrow.right", text: "连按同一快捷键 → 跨屏移动")
                    tipRow(icon: "hand.draw", text: "拖拽 NARC 圆点可移动位置")
                    tipRow(icon: "pin.fill", text: "⌃⌥P 固定当前窗口")
                }
            }
            .padding(16)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

/// A single shortcut reference row — non-interactive, display only.
struct ShortcutRow: View {
    let layout: WindowLayout

    var body: some View {
        HStack(spacing: 10) {
            // Layout icon
            Image(systemName: layout.iconName)
                .font(.system(size: 14))
                .foregroundColor(.primary.opacity(0.7))
                .frame(width: 20)

            // Layout name
            Text(layout.rawValue)
                .font(.system(size: 12))
                .foregroundColor(.primary)

            Spacer()

            // Hotkey badge
            Text(layout.hotkeyLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .padding(.vertical, 2)
    }
}
