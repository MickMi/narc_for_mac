import SwiftUI

// MARK: - Layout Thumbnail

/// Visual representation of where the window goes on screen.
struct LayoutThumbnail: View {
    let layout: WindowLayout

    var body: some View {
        GeometryReader { geo in
            let rect = layout.fractionalFrame
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.narcAccent.opacity(0.25))
                .frame(
                    width: geo.size.width * rect.width,
                    height: geo.size.height * rect.height
                )
                .offset(
                    x: geo.size.width * rect.origin.x,
                    y: geo.size.height * (1 - rect.origin.y - rect.height)
                )
        }
        .background(Color.narcSurfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.xs))
    }
}

// MARK: - Grid Cell

/// A single layout card in the grid — non-interactive, display only.
private struct LayoutGridCell: View {
    let layout: WindowLayout
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: NarcSpacing.xs) {
            // Thumbnail
            LayoutThumbnail(layout: layout)
                .aspectRatio(16 / 10, contentMode: .fit)

            // Layout name
            Text(layout.rawValue)
                .font(.narcCaption)
                .foregroundColor(.narcText)
                .lineLimit(1)

            // Hotkey badge
            Text(layout.hotkeyLabel)
                .font(.narcMonoSmall)
                .foregroundColor(.narcTextFaint)
        }
        .padding(NarcSpacing.sm)
        .background(Color.narcSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: NarcRadius.sm)
                .stroke(
                    isHovered ? Color.narcAccent : Color.narcBorder,
                    lineWidth: 0.5
                )
        )
        .animation(.narcEase, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Window Grid View

/// Window management tab content: visual layout grid reference.
/// All operations are performed via hotkeys — this view is informational only.
struct WindowGridView: View {
    @ObservedObject var windowManager: WindowManagerService

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NarcSpacing.lg) {
                // Header
                HStack(spacing: NarcSpacing.sm) {
                    Image(systemName: "keyboard")
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)
                    Text("Window Layouts")
                        .font(.narcSubtitle)
                        .foregroundColor(.narcTextMuted)
                    Spacer()
                }

                // 3-column layout grid
                LazyVGrid(columns: columns, spacing: NarcSpacing.sm) {
                    ForEach(WindowLayout.allCases) { layout in
                        LayoutGridCell(layout: layout)
                    }
                }

                Divider()
                    .padding(.vertical, NarcSpacing.xs)

                // Tips
                VStack(alignment: .leading, spacing: NarcSpacing.xs + 2) {
                    tipRow(icon: "arrow.left.arrow.right", text: "连按同一快捷键 → 跨屏移动")
                    tipRow(icon: "hand.draw", text: "拖拽 NARC 圆点可移动位置")
                    tipRow(icon: "pin.fill", text: "⌃⌥P 固定当前窗口")
                }
            }
            .padding(NarcSpacing.lg)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: icon)
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)
                .frame(width: NarcSpacing.lg)
            Text(text)
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)
        }
    }
}
