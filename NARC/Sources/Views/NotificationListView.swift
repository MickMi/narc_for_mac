import SwiftUI

/// Notification tab content: list of monitored apps, external Claude events,
/// and pinned windows. Three sections:
/// - **Monitoring**: IM badge tracking (WeChat, WeCom, Lark, ...)
/// - **Claude External**: pending approvals / notifications from Claude
///   sessions that are *not* running inside a NARC workspace tab (i.e. they
///   were launched in iTerm2 / Terminal.app / kitty / ghostty directly and
///   are reporting via the NARC Unix socket). The list mirrors the floating
///   widget's badge count, so the panel is no longer "less than" the badge.
/// - **Pinned**: user-pinned windows (sticky access to a specific window).
///
/// Workspace-internal Claude events (sessions NARC itself spawned in the
/// Dashboard) still surface only in the Dashboard sidebar — this panel
/// intentionally limits itself to *external* Claude events so we don't
/// double-route the user.
struct NotificationListView: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var claudeService: ClaudeSessionService
    @ObservedObject var pinnedWindowService: PinnedWindowService
    var onClose: () -> Void
    /// The screen where NARC's floating widget is located.
    var narcScreen: NSScreen?
    /// Keyboard selection state for ↑↓ navigation.
    @ObservedObject var keyboardSelection: KeyboardSelectionState

    var body: some View {
        let enabledStates = appMonitor.filteredStates
        let externalEvents = ClaudeExternalEvent.collect(
            approvals: claudeService.pendingApprovals,
            notifications: claudeService.notifications
        )
        let pinnedWindows = pinnedWindowService.pinnedWindows

        if enabledStates.isEmpty && externalEvents.isEmpty && pinnedWindows.isEmpty {
            emptyState
        } else {
            // Build flat index for keyboard navigation:
            // running monitoring apps → external Claude events → pinned windows.
            // This matches the visual section order in the body below.
            let runningStates = enabledStates.filter { $0.isRunning }
            let monitoringOffset = 0
            let claudeOffset = runningStates.count
            let pinnedOffset = claudeOffset + externalEvents.count

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
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
                                    keyboardIndex: kbIndex,
                                    isKeyboardSelected: kbIndex >= 0 && kbIndex == keyboardSelection.selectedIndex
                                ) {
                                    appMonitor.activateApp(
                                        bundleID: state.app.bundleID,
                                        summonToScreen: narcScreen
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

                        // MARK: - Claude External Section
                        if !externalEvents.isEmpty {
                            if !enabledStates.isEmpty {
                                Divider()
                                    .padding(.vertical, 4)
                            }

                            SectionHeader(title: "Claude External", icon: "terminal.fill")

                            ForEach(Array(externalEvents.enumerated()), id: \.element.id) { index, event in
                                let kbIndex = claudeOffset + index
                                ClaudeEventRow(
                                    event: event,
                                    keyboardIndex: kbIndex,
                                    isKeyboardSelected: kbIndex == keyboardSelection.selectedIndex
                                ) {
                                    // Jump to the source terminal window (iTerm / Terminal.app /
                                    // kitty / ghostty) via AppleScript. Same behavior as the
                                    // standalone toast notifications — NARC cannot reliably
                                    // surface an allow/deny UI for sessions it doesn't own.
                                    TerminalJumper.jump(
                                        tty: event.tty,
                                        cwd: event.cwd,
                                        projectName: event.projectName
                                    )
                                    onClose()
                                }
                                .id(kbIndex)

                                if event.id != externalEvents.last?.id {
                                    Divider()
                                        .padding(.leading, 64)
                                }
                            }
                        }

                        // MARK: - Pinned Section
                        if !pinnedWindows.isEmpty {
                            if !enabledStates.isEmpty || !externalEvents.isEmpty {
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
                                            summonToScreen: narcScreen
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
                .onChange(of: keyboardSelection.selectedIndex) { newIndex in
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
            Text("or press ⌃⌥P to pin a window")
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

            // Window info
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

            Spacer()

            // Action buttons (visible on hover)
            if isHovering {
                HStack(spacing: NarcSpacing.xs) {
                    // Toggle persistence: pin ↔ pin.fill
                    Button(action: onTogglePersistence) {
                        Image(systemName: pinned.isPersistent ? "pin.fill" : "pin")
                            .font(.narcCaption)
                            .foregroundStyle(pinned.isPersistent ? Color.narcAccent : Color.narcTextMuted)
                    }
                    .buttonStyle(.plain)
                    .help(pinned.isPersistent ? "Unlock (temporary)" : "Lock (persistent)")

                    // Remove
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.narcCaption)
                            .foregroundStyle(Color.narcTextMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
            } else {
                // Status indicator when not hovering
                if !isAlive {
                    // Gray dot — window/app not running
                    Circle()
                        .fill(Color.narcTextFaint)
                        .frame(width: NarcSize.statusDotSmall, height: NarcSize.statusDotSmall)
                } else {
                    // Persistence indicator
                    Image(systemName: pinned.isPersistent ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned.isPersistent ? Color.narcAccent : Color.narcTextFaint)
                }
            }
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .background(
            isKeyboardSelected ? Color.narcAccent.opacity(0.14) :
            (isHovering ? Color.narcSurfaceMuted : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onTap()
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

// MARK: - Claude External Event Wrapper

/// Unified view-model that flattens `PendingApproval` and `ClaudeNotification`
/// from `ClaudeSessionService` into a single row type for the panel list.
///
/// Only used for **external** events (those with `narcSessionId == nil`),
/// since workspace-internal events surface in the Dashboard sidebar instead.
/// The wrapper keeps a reference back to the originating model so the panel
/// could later wire up allow/deny/dismiss actions without re-resolving the
/// object from the service.
struct ClaudeExternalEvent: Identifiable, Equatable {
    let id: String  // Prefixed ("approval:" / "notification:") to keep ForEach keys unique
                    // even if two source events happened to mint the same UUID.
    let projectName: String
    let detail: String
    let isApproval: Bool
    let isHighRisk: Bool
    let toneColor: Color
    let iconName: String
    let tty: String?
    let cwd: String?
    let receivedAt: Date

    /// Filter to *external* events (narcSessionId == nil) and wrap each into a
    /// row-ready value. Approvals sort above notifications; within each
    /// group, most-recent-first. Pinned order:
    /// 1. High-risk approvals (e.g. `rm -rf`, `git push --force`)
    /// 2. Other approvals
    /// 3. Stopped notifications
    /// 4. Error notifications
    /// 5. Stale notifications
    static func collect(
        approvals: [PendingApproval],
        notifications: [ClaudeNotification]
    ) -> [ClaudeExternalEvent] {
        let externalApprovals = approvals
            .filter { $0.narcSessionId == nil }
            .map(ClaudeExternalEvent.init(approval:))
        let externalNotifications = notifications
            .filter { $0.narcSessionId == nil }
            .map(ClaudeExternalEvent.init(notification:))
        return (externalApprovals + externalNotifications).sorted { lhs, rhs in
            // Approvals always above notifications — they require an action.
            if lhs.isApproval != rhs.isApproval { return lhs.isApproval }
            // High-risk approvals rise to the top of their group.
            if lhs.isHighRisk != rhs.isHighRisk { return lhs.isHighRisk }
            // Within the same kind/risk class, newest first.
            return lhs.receivedAt > rhs.receivedAt
        }
    }

    init(approval: PendingApproval) {
        self.id = "approval:\(approval.id)"
        self.projectName = approval.projectName
        self.detail = approval.commandDescription
        self.isApproval = true
        self.isHighRisk = approval.isHighRisk
        // High-risk approvals get a danger tint to match ClaudeApprovalView's
        // visual language; benign approvals use the standard warn tone.
        self.toneColor = approval.isHighRisk ? .narcDanger : .narcWarn
        self.iconName = "exclamationmark.triangle.fill"
        self.tty = approval.tty
        self.cwd = approval.cwd
        self.receivedAt = approval.receivedAt
    }

    init(notification: ClaudeNotification) {
        self.id = "notification:\(notification.id)"
        self.projectName = notification.projectName
        self.detail = notification.message
        self.isApproval = false
        self.isHighRisk = false
        switch notification.type {
        case .stopped:
            self.toneColor = .narcInfo
            self.iconName = "bubble.left.fill"
        case .error:
            self.toneColor = .narcDanger
            self.iconName = "xmark.circle.fill"
        case .stale:
            self.toneColor = .narcWarn
            self.iconName = "clock.fill"
        }
        self.tty = notification.tty
        self.cwd = notification.cwd
        self.receivedAt = notification.timestamp
    }
}

// MARK: - Claude Event Row

/// A single external Claude event row in the notification list.
/// Visually mirrors `AppItemRow` (icon | name+detail | status), but the right
/// rail is a tone-colored dot that turns into a "jump" hint on hover, since
/// tapping the row invokes `TerminalJumper.jump(...)` to switch focus to
/// the source terminal window — not NARC's own window.
struct ClaudeEventRow: View {
    let event: ClaudeExternalEvent
    /// Keyboard navigation index (0-based). -1 means not navigable.
    var keyboardIndex: Int = -1
    /// Whether this row is currently selected via keyboard.
    var isKeyboardSelected: Bool = false
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: NarcSpacing.md) {
            // Keyboard shortcut number badge (matches AppItemRow / PinnedWindowRow)
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

            // Status icon (matches ClaudeToastView's circular tinted icon)
            ZStack {
                Circle()
                    .fill(event.toneColor.opacity(0.15))
                Image(systemName: event.iconName)
                    .font(.system(size: 13))
                    .foregroundStyle(event.toneColor)
            }
            .frame(width: NarcSize.appIconSize, height: NarcSize.appIconSize)

            // Project name + detail
            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                HStack(spacing: NarcSpacing.xs) {
                    Text(event.projectName)
                        .font(.narcSubtitle)
                        .fontWeight(event.isHighRisk ? .bold : .medium)
                        .foregroundStyle(Color.narcText)
                        .lineLimit(1)

                    // High-risk marker — visible at-a-glance even without hover.
                    if event.isHighRisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.narcCaption)
                            .foregroundStyle(Color.narcDanger)
                    }

                    // Approvals get an explicit "需要确认" pill so users can
                    // tell at a glance these need action, vs. informational
                    // notifications that don't.
                    if event.isApproval {
                        Text("需确认")
                            .font(.narcMonoTiny)
                            .foregroundStyle(Color.narcTextMuted)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: NarcRadius.xs)
                                    .fill(Color.narcSurfaceMuted)
                            )
                    }
                }

                Text(event.detail)
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Right rail: tone dot at rest, jump hint on hover
            if isHovering {
                Image(systemName: "arrow.up.right.square")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextMuted)
                    .help("跳转到终端窗口")
            } else {
                Circle()
                    .fill(event.toneColor)
                    .frame(width: NarcSize.statusDotSmall, height: NarcSize.statusDotSmall)
            }
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .background(
            isKeyboardSelected ? Color.narcAccent.opacity(0.14) :
            (isHovering ? Color.narcSurfaceMuted : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}
