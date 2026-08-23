import SwiftUI

/// Preferences window with tabbed navigation.
/// Receives `AppMonitorService` so the Widget tab can read/write the real
/// monitored-apps list (previously hardcoded @State).
struct PreferencesView: View {
    @ObservedObject var appMonitor: AppMonitorService

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("通用", systemImage: "gearshape") }

            WidgetTab(appMonitor: appMonitor)
                .tabItem { Label("悬浮窗", systemImage: "circle.fill") }

            ShortcutsTab()
                .tabItem { Label("快捷键", systemImage: "keyboard") }

            NotificationsTab(appMonitor: appMonitor)
                .tabItem { Label("通知", systemImage: "bell.fill") }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - Tab 1: General

struct GeneralTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("colorSchemeMode") private var colorSchemeMode = "system"

    private let themeOptions = [
        ("system", "跟随系统"),
        ("light", "浅色"),
        ("dark", "深色"),
    ]

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题模式", selection: $colorSchemeMode) {
                    ForEach(themeOptions, id: \.0) { opt in
                        Text(opt.1).tag(opt.0)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: colorSchemeMode) { _, mode in
                    switch mode {
                    case "light": NSApp.appearance = NSAppearance(named: .aqua)
                    case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
                    default:      NSApp.appearance = nil
                    }
                }
            }

            Section("系统行为") {
                Toggle("开机自动启动", isOn: $launchAtLogin)
                Toggle("显示菜单栏图标", isOn: $showMenuBarIcon)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Tab 2: Widget (悬浮窗)

struct WidgetTab: View {
    @ObservedObject var appMonitor: AppMonitorService
    @AppStorage("widgetSize") private var widgetSize = "Medium"
    @State private var showingAddSheet = false
    @State private var newAppBundleID = ""
    @State private var newAppName = ""

    private let sizeOptions = ["Small", "Medium", "Large"]

    var body: some View {
        Form {
            Section("监控对象") {
                if appMonitor.notificationStates.isEmpty {
                    Text("暂无监控对象")
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)
                } else {
                    ForEach(appMonitor.notificationStates) { state in
                        MonitoredAppRow(
                            state: state,
                            onToggle: { appMonitor.toggleApp(bundleID: state.app.bundleID) }
                        )
                    }
                }

                Button(action: { showingAddSheet = true }) {
                    Label("添加应用…", systemImage: "plus")
                }
            }

            Section("外观") {
                Picker("Widget 尺寸", selection: $widgetSize) {
                    ForEach(sizeOptions, id: \.self) { size in
                        Text(size).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("位置") {
                Button("重置悬浮窗位置到右下角") {
                    // Post a notification that AppDelegate listens for
                    NotificationCenter.default.post(name: .resetWidgetPosition, object: nil)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showingAddSheet) {
            AddAppSheet { bundleID, displayName in
                let app = MonitoredApp(id: bundleID, displayName: displayName, category: .other, isEnabled: true)
                appMonitor.addApp(app)
                showingAddSheet = false
            }
        }
    }
}

/// A single row in the monitored-apps list.
struct MonitoredAppRow: View {
    @ObservedObject var state: NotificationState
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: NarcSpacing.md) {
            // App icon
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: state.app.bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: NarcRadius.xs))
            } else {
                Image(systemName: "app.fill")
                    .frame(width: 24, height: 24)
                    .foregroundColor(.narcTextMuted)
            }

            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text(state.app.displayName)
                    .font(.narcBody)
                Text(state.app.bundleID)
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                    .lineLimit(1)
            }

            Spacer()

            // Running indicator
            Circle()
                .fill(state.isRunning ? Color.narcSuccess : Color.narcTextFaint)
                .frame(width: 6, height: 6)

            Toggle("", isOn: Binding(
                get: { state.app.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, NarcSpacing.xxs)
    }
}

/// Sheet for adding an app to the monitoring list.
/// Uses NSOpenPanel to pick a .app bundle directly — no more manual bundle ID entry.
struct AddAppSheet: View {
    var onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var bundleID = ""
    @State private var displayName = ""
    @State private var selectedAppURL: URL?

    var body: some View {
        VStack(spacing: NarcSpacing.lg) {
            Text("添加监控应用")
                .font(.narcTitle)

            // App picker
            VStack(spacing: NarcSpacing.sm) {
                Button(action: pickApp) {
                    if let url = selectedAppURL {
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName)
                                    .font(.narcSubtitle)
                                Text(bundleID)
                                    .font(.narcCaption)
                                    .foregroundColor(.narcTextMuted)
                            }
                            Spacer()
                            Text("更改…")
                                .font(.narcCaption)
                                .foregroundColor(.narcAccent)
                        }
                    } else {
                        HStack {
                            Image(systemName: "app.badge.plus")
                                .font(.system(size: 32))
                                .foregroundColor(.narcAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("选择应用")
                                    .font(.narcSubtitle)
                                    .foregroundColor(.narcAccent)
                                Text("点击浏览 /Applications 或其他位置")
                                    .font(.narcCaption)
                                    .foregroundColor(.narcTextMuted)
                            }
                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(NarcSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: NarcRadius.sm)
                        .fill(Color.narcSurfaceMuted)
                )
            }
            .padding(.horizontal)

            if !bundleID.isEmpty {
                Form {
                    TextField("显示名称（可修改）", text: $displayName)
                }
                .formStyle(.grouped)
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("添加") {
                    onAdd(bundleID, displayName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bundleID.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, NarcSpacing.xl)
        .frame(width: 420, height: 260)
    }

    /// Open NSOpenPanel to let the user pick a .app bundle.
    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "选择要监控的应用"
        panel.message = "选择一个应用程序，NARC 将监控其 Dock Badge"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // Restrict to .app bundles and /Applications
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedAppURL = url

        // Extract bundle ID and display name from the selected app's Info.plist
        let infoPlist = url.appendingPathComponent("Contents/Info.plist")
        if let plist = NSDictionary(contentsOf: infoPlist) {
            bundleID = plist["CFBundleIdentifier"] as? String ?? url.deletingPathExtension().lastPathComponent
            displayName = plist["CFBundleDisplayName"] as? String
                ?? plist["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
        } else {
            bundleID = url.deletingPathExtension().lastPathComponent
            displayName = bundleID
        }
    }
}

// MARK: - Tab 3: Shortcuts

struct ShortcutsTab: View {
    /// Layout shortcuts grouped by modifier.
    private let layoutShortcuts: [(WindowLayout, String)] = WindowLayout.allCases.map { layout in
        (layout, layout.hotkeyLabel)
    }

    var body: some View {
        Form {
            Section("窗口布局快捷键") {
                ForEach(layoutShortcuts, id: \.0.id) { layout, hotkey in
                    HStack {
                        Image(systemName: layout.iconName)
                            .frame(width: NarcSpacing.xl)
                            .foregroundColor(.narcTextMuted)
                        Text(layout.rawValue)
                            .font(.narcBody)
                        Spacer()
                        ShortcutBadge(label: hotkey)
                    }
                    .padding(.vertical, NarcSpacing.xxs)
                }
            }

            Section("全局快捷键") {
                ShortcutRow(label: "钉选窗口", hotkey: "⌃⌥P")
                ShortcutRow(label: "切换面板", hotkey: "⌃⌥N")
            }

            Section {
                VStack(alignment: .leading, spacing: NarcSpacing.xs) {
                    Text("快捷键自定义即将推出")
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)
                    Text("当前快捷键需要辅助功能权限。前往 系统设置 → 隐私与安全性 → 辅助功能 授权。")
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Row showing a shortcut label with icon + badge.
private struct ShortcutRow: View {
    let label: String
    let hotkey: String

    var body: some View {
        HStack {
            Text(label)
                .font(.narcBody)
            Spacer()
            ShortcutBadge(label: hotkey)
        }
        .padding(.vertical, NarcSpacing.xxs)
    }
}

/// Visual badge for a keyboard shortcut.
private struct ShortcutBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.narcMono)
            .foregroundColor(.narcTextMuted)
            .padding(.horizontal, NarcSpacing.sm)
            .padding(.vertical, NarcSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: NarcRadius.xs)
                    .fill(Color.narcSurfaceMuted)
            )
    }
}

// MARK: - Retained Workspace settings (not exposed in PreferencesView)

struct WorkspaceTab: View {
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 13
    @AppStorage("windowSnapEnabled") private var windowSnapEnabled = false
    @AppStorage("playNotificationSound") private var playNotificationSound = true
    @AppStorage(AppDelegate.workspaceCloseActionKey) private var workspaceCloseAction = "ask"

    private let closeActionLabels: [String: String] = [
        "ask": "每次询问",
        "hide": "收起窗口（保留终端）",
        "terminate": "关闭终端",
    ]

    var body: some View {
        Form {
            Section("终端") {
                HStack {
                    Text("默认字体大小")
                        .font(.narcBody)
                    Spacer()
                    Text("\(Int(terminalFontSize)) pt")
                        .font(.narcMono)
                        .foregroundColor(.narcTextMuted)
                        .frame(minWidth: 36, alignment: .trailing)
                    Slider(value: $terminalFontSize, in: 10...24, step: 1)
                        .frame(width: 140)
                }
            }

            Section("窗口管理") {
                Toggle("拖拽吸附到边缘", isOn: $windowSnapEnabled)
                    .onChange(of: windowSnapEnabled) { _, enabled in
                        if enabled {
                            WindowSnapService.shared.start()
                        } else {
                            WindowSnapService.shared.stop()
                        }
                    }
            }

            Section("关闭行为") {
                HStack {
                    Text("⌘W / 关闭按钮")
                        .font(.narcBody)
                    Spacer()
                    Text(closeActionLabels[workspaceCloseAction] ?? "每次询问")
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)
                }

                if workspaceCloseAction != "ask" {
                    Button("重置为「每次询问」") {
                        workspaceCloseAction = "ask"
                    }
                }
            }

            Section("通知") {
                Toggle("Claude 回答时播放提示音", isOn: $playNotificationSound)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Tab 5: Notifications (Filter Rules)

struct NotificationsTab: View {
    @ObservedObject var appMonitor: AppMonitorService
    @State private var showingAddSheet = false

    private let availableApps: [(id: String, name: String)] = [
        ("*", "所有应用"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            if appMonitor.filters.isEmpty {
                VStack(spacing: NarcSpacing.md) {
                    Spacer()
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.narcDisplayXL)
                        .foregroundColor(.narcTextMuted)
                    Text("暂无过滤规则")
                        .font(.narcSubtitle)
                    Text("添加规则来自定义哪些通知高亮、静音或隐藏。")
                        .font(.narcBody)
                        .foregroundColor(.narcTextMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    Spacer()
                }
            } else {
                List {
                    ForEach(appMonitor.filters) { filter in
                        FilterRuleRow(
                            filter: filter,
                            appName: appName(for: filter.appBundleID),
                            onToggle: {
                                var updated = filter
                                updated.isEnabled.toggle()
                                appMonitor.updateFilter(updated)
                            }
                        )
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            appMonitor.removeFilter(id: appMonitor.filters[idx].id)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(action: { showingAddSheet = true }) {
                    Label("添加规则", systemImage: "plus")
                }

                Spacer()

                Text("\(appMonitor.filters.count) 条规则")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
            }
            .padding(NarcSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingAddSheet) {
            AddFilterSheet(availableApps: availableApps + appMonitor.notificationStates.map {
                (id: $0.app.bundleID, name: $0.app.displayName)
            }) { newFilter in
                appMonitor.addFilter(newFilter)
            }
        }
    }

    private func appName(for bundleID: String) -> String {
        if bundleID == "*" { return "所有应用" }
        return appMonitor.notificationStates
            .first(where: { $0.app.bundleID == bundleID })?
            .app.displayName ?? bundleID
    }
}

// MARK: - Shared Components

/// A single filter rule row.
struct FilterRuleRow: View {
    let filter: NotificationFilter
    let appName: String
    var onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                HStack(spacing: NarcSpacing.xs) {
                    Circle()
                        .fill(filter.isEnabled ? Color.narcSuccess : Color.narcBorder)
                        .frame(width: NarcSize.statusDotSmall, height: NarcSize.statusDotSmall)
                        .onTapGesture { onToggle() }

                    Text(appName)
                        .font(.narcBody)

                    Text("•")
                        .foregroundColor(.narcTextMuted)

                    Text(filter.filterType.rawValue)
                        .font(.narcBody)
                        .foregroundColor(.narcTextMuted)
                }

                if !filter.pattern.isEmpty && filter.filterType == .badgeThreshold {
                    Text("阈值: \(filter.pattern)")
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)
                } else if !filter.pattern.isEmpty && filter.filterType == .keyword {
                    Text("关键词: \(filter.pattern)")
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)
                }
            }

            Spacer()

            // Action badge
            Text(filter.action.rawValue)
                .font(.narcCaption)
                .foregroundColor(actionColor(filter.action))
                .padding(.horizontal, NarcSpacing.sm)
                .padding(.vertical, NarcSpacing.xs)
                .background(
                    Capsule()
                        .fill(actionColor(filter.action).opacity(0.12))
                )
        }
    }

    private func actionColor(_ action: NotificationFilter.FilterAction) -> Color {
        switch action {
        case .highlight: return .narcWarn
        case .normal: return .narcInfo
        case .silent: return .narcTextFaint
        case .hide: return .narcDanger
        }
    }
}

/// Sheet for adding a new filter rule.
struct AddFilterSheet: View {
    let availableApps: [(id: String, name: String)]
    var onAdd: (NotificationFilter) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedAppID = "*"
    @State private var filterType: NotificationFilter.FilterType = .badgeThreshold
    @State private var pattern = "1"
    @State private var action: NotificationFilter.FilterAction = .highlight

    var body: some View {
        VStack(spacing: NarcSpacing.lg) {
            Text("添加过滤规则")
                .font(.narcTitle)

            Form {
                Picker("应用", selection: $selectedAppID) {
                    ForEach(availableApps, id: \.id) { app in
                        Text(app.name).tag(app.id)
                    }
                }

                Picker("类型", selection: $filterType) {
                    ForEach(NotificationFilter.FilterType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                if filterType == .badgeThreshold {
                    TextField("Badge 阈值（如 3）", text: $pattern)
                } else if filterType == .keyword {
                    TextField("匹配关键词", text: $pattern)
                }

                Picker("动作", selection: $action) {
                    ForEach(NotificationFilter.FilterAction.allCases, id: \.self) { act in
                        Text(act.rawValue).tag(act)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("添加") {
                    let filter = NotificationFilter(
                        appBundleID: selectedAppID,
                        filterType: filterType,
                        pattern: pattern,
                        action: action
                    )
                    onAdd(filter)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(NarcSpacing.xl)
        .frame(width: 400, height: 340)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let resetWidgetPosition = Notification.Name("narc.resetWidgetPosition")
}
