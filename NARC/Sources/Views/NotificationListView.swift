import SwiftUI

/// Notification tab content: list of monitored apps and pinned windows.
/// Two sections:
/// - **Monitoring**: IM badge tracking (WeChat, WeCom, Lark, ...)
/// - **Pinned**: user-pinned windows (sticky access to a specific window).
struct NotificationListView: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var pinnedWindowService: PinnedWindowService
    @ObservedObject var hotkeyService: HotkeyService
    var onClose: () -> Void
    /// Resolves the floating widget's current screen at action time.
    var narcScreenProvider: () -> NSScreen?
    /// Keyboard selection state for ↑↓ navigation.
    @ObservedObject var keyboardSelection: KeyboardSelectionState

    var body: some View {
        let enabledStates = appMonitor.filteredStates
        let pinnedWindows = pinnedWindowService.pinnedWindows

        if enabledStates.isEmpty && pinnedWindows.isEmpty {
            emptyState
        } else {
            // Build flat index for keyboard navigation:
            // running monitoring apps → pinned windows.
            // This matches the visual section order in the body below.
            let runningStates = enabledStates.filter { $0.isRunning }
            let monitoringOffset = 0
            let pinnedOffset = monitoringOffset + runningStates.count

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if appMonitor.isBadgeStatusUncertain {
                            Label(
                                "部分未读暂不可确认，显示上次可信结果",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.narcCaption)
                            .foregroundStyle(Color.narcWarn)
                            .padding(.horizontal, NarcSpacing.lg)
                            .padding(.vertical, NarcSpacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.narcWarn.opacity(0.08))
                        }

                        // MARK: - Monitoring Section
                        if !enabledStates.isEmpty {
                            SectionHeader(title: "Monitoring", icon: "bell.fill")

                            ForEach(Array(enabledStates.enumerated()), id: \.element.id) { _, state in
                                let filterAction = appMonitor.resolveFilterAction(for: state)
                                // Only running apps get a keyboard index
                                let kbIndex = state.isRunning
                                    ? monitoringOffset + runningStates.firstIndex(where: { $0.id == state.id })!
                                    : -1
                                AppItemRow(
                                    state: state,
                                    filterAction: filterAction,
                                    isBadgeUncertain: appMonitor.uncertainBundleIDs.contains(
                                        state.app.bundleID
                                    ),
                                    keyboardIndex: kbIndex,
                                    isKeyboardSelected: kbIndex >= 0 && kbIndex == keyboardSelection.selectedIndex
                                ) {
                                    appMonitor.activateApp(
                                        bundleID: state.app.bundleID,
                                        summonToScreen: narcScreenProvider()
                                    )
                                    onClose()
                                }
                                .id(kbIndex)

                                if state.id != enabledStates.last?.id {
                                    Divider()
                                        .padding(.leading, 64)
                                }
                            }
                        }

                        // MARK: - Pinned Section
                        if !pinnedWindows.isEmpty {
                            if !enabledStates.isEmpty {
                                Divider()
                                    .padding(.vertical, 4)
                            }

                            SectionHeader(title: "Pinned", icon: "pin.fill")

                            ForEach(Array(pinnedWindows.enumerated()), id: \.element.id) { index, pinned in
                                let runtimeState = pinnedWindowService.runtimeStates[pinned.id]
                                let kbIndex = pinnedOffset + index
                                PinnedWindowRow(
                                    pinned: pinned,
                                    runtimeState: runtimeState,
                                    keyboardIndex: kbIndex,
                                    isKeyboardSelected: kbIndex == keyboardSelection.selectedIndex,
                                    onTap: {
                                        pinnedWindowService.activatePinnedWindow(
                                            pinned,
                                            summonToScreen: narcScreenProvider()
                                        )
                                        onClose()
                                    },
                                    onTogglePersistence: {
                                        pinnedWindowService.togglePersistence(id: pinned.id)
                                    },
                                    onRemove: {
                                        pinnedWindowService.unpin(id: pinned.id)
                                    }
                                )
                                .id(kbIndex)

                                if pinned.id != pinnedWindows.last?.id {
                                    Divider()
                                        .padding(.leading, 64)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: keyboardSelection.selectedIndex) { _, newIndex in
                    if newIndex >= 0 {
                        withAnimation(.narcEase) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: NarcSpacing.md) {
            Spacer()
            Image(systemName: "moon.zzz")
                .font(.system(size: 36))
                .foregroundStyle(Color.narcTextMuted)
            Text("No monitored apps")
                .font(.narcSubtitle)
                .foregroundStyle(Color.narcText)
            Text("Go to Settings to add apps →")
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)
            Text(hotkeyService.activeShortcut(for: .toggleCurrentWindowPin).map { "or press \($0.displayLabel) to mark a window" } ?? "Enable the marking shortcut in Preferences")
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Section Header

/// A section header with icon and title.
struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: NarcSpacing.xs) {
            Image(systemName: icon)
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)
            Text(title)
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)
            Spacer()
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.top, NarcSpacing.sm)
        .padding(.bottom, NarcSpacing.xs)
    }
}

// MARK: - Pinned Window Row

/// A single pinned window row in the notification list.
struct PinnedWindowRow: View {
    let pinned: PinnedWindow
    let runtimeState: PinnedWindowRuntimeState?
    /// Keyboard navigation index (0-based). -1 means not navigable.
    var keyboardIndex: Int = -1
    /// Whether this row is currently selected via keyboard.
    var isKeyboardSelected: Bool = false
    var onTap: () -> Void
    var onTogglePersistence: () -> Void
    var onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: NarcSpacing.xs) {
            // Recall and maintenance are siblings: clicking a pin must never
            // also recall the window and close the panel.
            Button(action: onTap) {
                HStack(spacing: NarcSpacing.md) {
                    if keyboardIndex >= 0 && keyboardIndex < 10 {
                        Text("\(keyboardIndex + 1 < 10 ? keyboardIndex + 1 : 0)")
                            .font(.narcMonoTiny)
                            .foregroundColor(isKeyboardSelected ? .white : Color.narcTextMuted)
                            .frame(width: NarcSize.keyBadgeSize, height: NarcSize.keyBadgeSize)
                            .background(
                                RoundedRectangle(cornerRadius: NarcRadius.xs)
                                    .fill(isKeyboardSelected ? Color.narcAccent : Color.narcSurfaceMuted)
                            )
                    }

                    appIcon

                    VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                        Text(displayTitle)
                            .font(.narcBody)
                            .foregroundStyle(isAlive ? Color.narcText : Color.narcTextMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(pinned.appDisplayName)
                            .font(.narcCaption)
                            .foregroundStyle(Color.narcTextMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: NarcSpacing.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, NarcSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("召回窗口：\(displayTitle)")
            .accessibilityIdentifier("pinned-window.recall.\(pinned.id)")

            // Keep both targets present and equally sized in every hover and
            // runtime state. Hover may change emphasis, never target identity.
            HStack(spacing: NarcSpacing.xs) {
                Button(action: onTogglePersistence) {
                    Image(systemName: pinned.isPersistent ? "pin.fill" : "pin")
                        .font(.narcCaption)
                        .foregroundStyle(pinned.isPersistent ? Color.narcAccent : Color.narcTextMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(pinned.isPersistent ? "改为临时标记：退出 NARC 后不保留" : "长期保留：重启 NARC 后仍保留")
                .accessibilityLabel(pinned.isPersistent ? "取消长期保留" : "长期保留此窗口")
                .accessibilityValue(pinned.isPersistent ? "长期保留" : "临时")
                .accessibilityIdentifier("pinned-window.persistence.\(pinned.id)")

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.narcCaption)
                        .foregroundStyle(isHovering ? Color.narcTextMuted : Color.narcTextFaint)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("移除标记（不关闭窗口）")
                .accessibilityLabel("移除此窗口标记")
                .accessibilityIdentifier("pinned-window.remove.\(pinned.id)")
            }
        }
        .padding(.horizontal, NarcSpacing.lg)
        .background(
            isKeyboardSelected ? Color.narcAccent.opacity(0.14) :
            (isHovering ? Color.narcSurfaceMuted : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Helpers

    private var isAlive: Bool {
        runtimeState?.isAlive ?? false
    }

    private var displayTitle: String {
        runtimeState?.currentTitle ?? pinned.windowTitle
    }

    private var appIcon: some View {
        Group {
            if let icon = getAppIcon(bundleID: pinned.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: NarcSize.windowIconSize, height: NarcSize.windowIconSize)
                    .clipShape(RoundedRectangle(cornerRadius: NarcRadius.xs))
                    .opacity(isAlive ? 1.0 : 0.5)
            } else {
                RoundedRectangle(cornerRadius: NarcRadius.xs)
                    .fill(Color.narcSurfaceMuted)
                    .frame(width: NarcSize.windowIconSize, height: NarcSize.windowIconSize)
                    .overlay {
                        Image(systemName: "macwindow")
                            .font(.narcCaption)
                            .foregroundStyle(Color.narcTextMuted)
                    }
            }
        }
    }

    private func getAppIcon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - App Item Row (Monitoring)

/// A single app item row in the notification list.
struct AppItemRow: View {
    @ObservedObject var state: NotificationState
    var filterAction: NotificationFilter.FilterAction = .normal
    var isBadgeUncertain = false
    /// Keyboard navigation index (0-based). -1 means not navigable.
    var keyboardIndex: Int = -1
    /// Whether this row is currently selected via keyboard.
    var isKeyboardSelected: Bool = false
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: NarcSpacing.md) {
            // Keyboard shortcut number badge
            if keyboardIndex >= 0 && keyboardIndex < 10 {
                Text("\(keyboardIndex + 1 < 10 ? keyboardIndex + 1 : 0)")
                    .font(.narcMonoTiny)
                    .foregroundColor(isKeyboardSelected ? .white : Color.narcTextMuted)
                    .frame(width: NarcSize.keyBadgeSize, height: NarcSize.keyBadgeSize)
                    .background(
                        RoundedRectangle(cornerRadius: NarcRadius.xs)
                            .fill(isKeyboardSelected ? Color.narcAccent : Color.narcSurfaceMuted)
                    )
            }

            // App icon
            appIcon

            // App info
            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                HStack(spacing: NarcSpacing.xs) {
                    Text(state.app.displayName)
                        .font(.narcSubtitle)
                        .fontWeight(filterAction == .highlight ? .bold : .medium)
                        .foregroundStyle(filterAction == .silent ? Color.narcTextMuted : Color.narcText)

                    // Highlight indicator
                    if filterAction == .highlight && state.hasNewNotification {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.narcCaption)
                            .foregroundStyle(Color.narcWarn)
                    }
                }

                Text(state.isRunning ? state.app.category.rawValue : "Not running")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextMuted)
            }

            Spacer()

            // Status indicator
            statusIndicator
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .background(
            isKeyboardSelected ? Color.narcAccent.opacity(0.14) :
            (isHovering ? Color.narcSurfaceMuted :
            (filterAction == .highlight && state.hasNewNotification ? Color.narcWarn.opacity(0.06) : Color.clear))
        )
        .opacity(filterAction == .silent ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if state.isRunning {
                onTap()
            }
        }
    }

    // MARK: - App Icon

    private var appIcon: some View {
        Group {
            if let icon = getAppIcon(bundleID: state.app.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: NarcSize.appIconSize, height: NarcSize.appIconSize)
                    .clipShape(RoundedRectangle(cornerRadius: NarcRadius.sm))
            } else {
                RoundedRectangle(cornerRadius: NarcRadius.sm)
                    .fill(Color.narcSurfaceMuted)
                    .frame(width: NarcSize.appIconSize, height: NarcSize.appIconSize)
                    .overlay {
                        Image(systemName: "app.fill")
                            .foregroundStyle(Color.narcTextMuted)
                    }
            }
        }
    }

    /// Get the app icon from its bundle ID.
    private func getAppIcon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        if !state.isRunning {
            // Gray dot — not running
            Circle()
                .fill(Color.narcTextFaint)
                .frame(width: NarcSize.keyBadgeSize, height: NarcSize.keyBadgeSize)
        } else if isBadgeUncertain {
            Text(BadgePresentation.resolve(
                count: state.badgeCount,
                isUncertain: true
            ).text ?? "?")
            .font(.narcMonoSmall)
            .foregroundStyle(Color.narcWarn)
            .padding(.horizontal, NarcSpacing.xs)
            .frame(minWidth: 22, minHeight: 22)
            .background(Color.narcWarn.opacity(0.14))
            .clipShape(Capsule())
            .help("未读暂不可确认，已保留上次可信结果")
            .accessibilityLabel("未读暂不可确认，已保留上次可信结果")
        } else if state.hasNewNotification {
            // Accent badge with count
            ZStack {
                Capsule()
                    .fill(Color.narcDanger)
                    .frame(minWidth: 22, maxHeight: 22)

                Text("\(state.badgeCount)")
                    .font(.narcMonoSmall)
                    .foregroundStyle(.white)
                    .padding(.horizontal, NarcSpacing.xs)
            }
            .fixedSize()
        } else {
            // Green checkmark — running, no notifications
            ZStack {
                Circle()
                    .fill(Color.narcSuccess.opacity(0.2))
                    .frame(width: 22, height: 22)

                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.narcSuccess)
            }
        }
    }
}
