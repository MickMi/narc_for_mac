import Cocoa
import SwiftUI

enum PinnedWindowSwitcherLayout {
    static let width: CGFloat = 380
    static let rowHeight: CGFloat = 58
    static let chromeHeight: CGFloat = 116
    static let emptyHeight: CGFloat = 190
    static let maximumHeight: CGFloat = 464

    static func panelSize(itemCount: Int) -> NSSize {
        guard itemCount > 0 else {
            return NSSize(width: width, height: emptyHeight)
        }
        return NSSize(
            width: width,
            height: min(maximumHeight, chromeHeight + CGFloat(itemCount) * rowHeight)
        )
    }

    static func frame(itemCount: Int, in visibleFrame: NSRect) -> NSRect {
        let size = panelSize(itemCount: itemCount)
        let x = visibleFrame.midX - size.width / 2
        let centeredY = visibleFrame.midY - size.height / 2
        let y = min(
            visibleFrame.maxY - size.height - 24,
            max(visibleFrame.minY + 24, centeredY + visibleFrame.height * 0.08)
        )
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}

/// Keyboard-first launcher for exact windows that the user has marked.
///
/// The underlying `PanelWindow` is shared with the main panel, but this content
/// is deliberately independent: it opens directly on the mouse's display and
/// never includes monitored applications in its numeric slots.
struct PinnedWindowSwitcherView: View {
    @ObservedObject var pinnedWindowService: PinnedWindowService
    @ObservedObject var hotkeyService: HotkeyService
    @ObservedObject var selection: PinnedWindowSwitcherSelectionState
    let onActivate: (PinnedWindow) -> Void
    let onClose: () -> Void
    let onItemCountChanged: (Int) -> Void

    private var pins: [PinnedWindow] {
        // Array order is the stable slot order. It changes only when the user
        // explicitly marks, removes, or changes persistence for a window.
        pinnedWindowService.pinnedWindows
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if pins.isEmpty {
                emptyState
            } else {
                pinList
            }

            footer
        }
        .frame(
            width: PinnedWindowSwitcherLayout.panelSize(itemCount: pins.count).width,
            height: PinnedWindowSwitcherLayout.panelSize(itemCount: pins.count).height
        )
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NarcRadius.xl, style: .continuous)
                .strokeBorder(Color.narcBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        .onAppear {
            selection.clamp(itemCount: pins.count)
        }
        .onChange(of: pins.map(\.id)) { _, ids in
            selection.clamp(itemCount: ids.count)
            onItemCountChanged(ids.count)
        }
    }

    private var header: some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "pin.fill")
                .font(.narcSubtitle)
                .foregroundColor(.narcAccent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text("已标记窗口")
                    .font(.narcSubtitle)
                    .foregroundColor(.narcText)
                Text("直接选择一个具体窗口")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.narcBody)
                    .foregroundColor(.narcTextMuted)
            }
            .buttonStyle(.plain)
            .help("关闭（Esc）")
            .accessibilityLabel("关闭已标记窗口")
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.md)
    }

    private var pinList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pins.enumerated()), id: \.element.id) { index, pinned in
                        PinnedWindowRow(
                            pinned: pinned,
                            runtimeState: pinnedWindowService.runtimeStates[pinned.id],
                            keyboardIndex: index < 9 ? index : -1,
                            isKeyboardSelected: index == selection.selectedIndex,
                            onTap: { onActivate(pinned) },
                            onTogglePersistence: {
                                pinnedWindowService.togglePersistence(id: pinned.id)
                            },
                            onRemove: {
                                pinnedWindowService.unpin(id: pinned.id)
                            }
                        )
                        .id(index)

                        if pinned.id != pins.last?.id {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
                .padding(.vertical, NarcSpacing.xs)
            }
            .onChange(of: selection.selectedIndex) { _, index in
                guard index >= 0 else { return }
                withAnimation(.narcEase) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: NarcSpacing.sm) {
            Spacer(minLength: NarcSpacing.md)
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.narcTextMuted)
                .accessibilityHidden(true)
            Text("还没有标记窗口")
                .font(.narcBody)
                .foregroundColor(.narcText)
            Text(hotkeyService.activeShortcut(for: .toggleCurrentWindowPin).map { "切到目标窗口后按 \($0.displayLabel)" } ?? "标记快捷键未启用，请到偏好设置修改")
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)
            Spacer(minLength: NarcSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: NarcSpacing.sm) {
            shortcutHint("1–9", label: "直达")
            shortcutHint("↑↓", label: "选择")
            shortcutHint("↩", label: "召回")

            Spacer()

            Text(hotkeyService.activeShortcut(for: .toggleCurrentWindowPin).map { "\($0.displayLabel) 标记 / 取消" } ?? "标记快捷键未启用")
                .font(.narcMonoTiny)
                .foregroundColor(.narcTextMuted)
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .background(Color.narcBackground)
    }

    private func shortcutHint(_ key: String, label: String) -> some View {
        HStack(spacing: NarcSpacing.xxs) {
            Text(key)
                .font(.narcMonoTiny)
                .padding(.horizontal, NarcSpacing.xs)
                .padding(.vertical, NarcSpacing.xxs)
                .background(Color.narcSurfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: NarcRadius.xs / 2))
            Text(label)
                .font(.narcMonoTiny)
                .foregroundColor(.narcTextMuted)
        }
    }
}
