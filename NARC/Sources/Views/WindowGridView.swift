import SwiftUI

/// Window management tab content: grid of layout buttons.
struct WindowGridView: View {
    @ObservedObject var windowManager: WindowManagerService

    // Layout grid: 3 columns
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(WindowLayout.allCases) { layout in
                    LayoutButton(layout: layout) {
                        windowManager.moveWindow(to: layout)
                    }
                }
            }
            .padding(16)
        }
    }
}

/// A single layout button in the window management grid.
struct LayoutButton: View {
    let layout: WindowLayout
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Layout thumbnail
                layoutThumbnail
                    .frame(width: 40, height: 28)

                // Layout name
                Text(layout.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Hotkey label
                Text(layout.hotkeyLabel)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Layout Thumbnail

    private var layoutThumbnail: some View {
        Image(systemName: layout.iconName)
            .font(.system(size: 20))
            .foregroundColor(isHovering ? .accentColor : .secondary)
    }
}
