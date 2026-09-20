import SwiftUI
import Carbon

/// Preferences window with tabbed navigation.
/// Receives the shared runtime services so Preferences always reflects the
/// monitoring state and shortcut that are actually active.
struct PreferencesView: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var hotkeyService: HotkeyService
    @ObservedObject var reminderSettings: TodoReminderSettings
    @ObservedObject var codexCompletionService: CodexCompletionService
    var onPreviewReminder: () -> Void

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("通用", systemImage: "gearshape") }

            WidgetTab(appMonitor: appMonitor, hotkeyService: hotkeyService)
                .tabItem { Label("悬浮球", systemImage: "circle.fill") }

            ShortcutsTab(hotkeyService: hotkeyService)
                .tabItem { Label("快捷键", systemImage: "keyboard") }

            NotificationsTab(appMonitor: appMonitor)
                .tabItem { Label("通知", systemImage: "bell.fill") }

            TodoRemindersTab(settings: reminderSettings, onPreview: onPreviewReminder)
                .tabItem { Label("提醒", systemImage: "clock") }

            CodexReminderSettingsView(service: codexCompletionService)
                .tabItem { Label("AI 回复", systemImage: "bubble.left.and.bubble.right") }
        }
        .frame(width: 560, height: 460)
    }
}

struct TodoRemindersTab: View {
    @ObservedObject var settings: TodoReminderSettings
    let onPreview: () -> Void
    @State private var error: String?

    var body: some View {
        Form {
            Section("每日待办回顾") {
                Toggle("开启每日提醒", isOn: Binding(
                    get: { settings.configuration.isEnabled },
                    set: { _ = settings.update(isEnabled: $0) }
                ))
                Text("按本机时间，在悬浮球旁提示下一件事和其他待办，不抢走当前输入焦点。")
                    .font(.narcCaption).foregroundStyle(.secondary)
                ForEach(settings.configuration.minutes, id: \.self) { minute in
                    HStack {
                        DatePicker("每天", selection: Binding(
                            get: { date(for: minute) },
                            set: { replace(minute, with: $0) }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel("每日提醒时间 \(label(for: minute))")
                        Spacer()
                        Button {
                            _ = settings.update(minutes: settings.configuration.minutes.filter { $0 != minute })
                            error = nil
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("删除 \(label(for: minute)) 提醒")
                    }
                }
                Button("添加提醒时间", systemImage: "plus") {
                    let used = Set(settings.configuration.minutes)
                    let preferred = [9 * 60, 18 * 60, 21 * 60] + Array(0..<1440)
                    if let minute = preferred.first(where: { !used.contains($0) }) {
                        _ = settings.update(minutes: settings.configuration.minutes + [minute])
                        error = nil
                    }
                }
                .disabled(settings.configuration.minutes.count == 1440)
                if settings.configuration.minutes.isEmpty {
                    Text("还没有提醒时间，添加后才会自动提醒。")
                        .font(.narcCaption).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.narcCaption).foregroundStyle(.red) }
            }
            Section("提醒内容") {
                Text("先展示你指定的下一件事；未指定时按高、普通、低优先级排列，同级截止时间早的优先。其余待办最多预览 3 项。")
                    .font(.narcCaption).foregroundStyle(.secondary)
                Text("在 Todo 的“安排”中调整优先级、截止时间或指定下一件事。无待办不提醒；错过超过 10 分钟不追补。NARC 需保持运行。")
                    .font(.narcCaption).foregroundStyle(.secondary)
                Button("预览提醒（不修改待办）", action: onPreview)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func date(for minute: Int) -> Date {
        // A reference day avoids elapsed-second arithmetic across DST changes.
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15,
                                                    hour: minute / 60, minute: minute % 60)) ?? Date()
    }

    private func label(for minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private func replace(_ minute: Int, with date: Date) {
        let calendar = Calendar.current
        let replacement = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        guard replacement != minute else { return }
        let next = settings.configuration.minutes.map { $0 == minute ? replacement : $0 }
        error = settings.update(minutes: next) ? nil : "这个提醒时间已经存在。"
    }
}

// MARK: - Tab 1: General

struct GeneralTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
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
                LabeledContent {
                    Text("始终显示")
                        .foregroundColor(.narcTextMuted)
                } label: {
                    Label("菜单栏与悬浮球", systemImage: "menubar.rectangle")
                }

                Text("NARC 不显示 Dock 图标；菜单栏负责持续状态，桌面悬浮球负责当前注意力。")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Tab 2: Floating Widget and Monitoring

struct WidgetTab: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var hotkeyService: HotkeyService
    @AppStorage("widgetSize") private var widgetSize = "Medium"
    @State private var showingAddSheet = false
    @State private var newAppBundleID = ""
    @State private var newAppName = ""

    private let sizeOptions = [
        ("Small", "小"),
        ("Medium", "中"),
        ("Large", "大"),
    ]

    var body: some View {
        Form {
            Section("注意力锚点") {
                Text(hotkeyService.activeShortcut(for: .summonWidget).map {
                    "按 \($0.displayLabel) 可把悬浮球召回鼠标所在屏幕，并展开它旁边的面板。"
                } ?? "点击菜单栏 N 可召回悬浮球；召回快捷键尚未启用，可到快捷键设置查看原因。")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)

                Picker("悬浮球尺寸", selection: $widgetSize) {
                    ForEach(sizeOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .pickerStyle(.segmented)

                Button("重置到当前屏幕右下角") {
                    NotificationCenter.default.post(name: .resetWidgetPosition, object: nil)
                }
            }

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

            Section {
                Text("这里管理悬浮球面板中的应用级未读；目标 App 未向 macOS 暴露 Dock Badge 时，状态会标记为不可确认。")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
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
    @ObservedObject var hotkeyService: HotkeyService
    @State private var editingAction: ConfigurableHotkeyAction?
    @State private var showsGlobalActions = true
    @State private var showsWindowLayouts = false
    @State private var actionFailureMessages: [ConfigurableHotkeyAction: String] = [:]

    var body: some View {
        Form {
            Section {
                shortcutGroup(
                    "全局操作",
                    actions: ConfigurableHotkeyAction.globalActions,
                    isExpanded: $showsGlobalActions,
                    identifier: "shortcut-group-global"
                )
            }

            Section {
                shortcutGroup(
                    "窗口布局",
                    actions: ConfigurableHotkeyAction.layoutActions,
                    isExpanded: $showsWindowLayouts,
                    identifier: "shortcut-group-layouts"
                )
            }

            Section {
                Text("应用后立即生效，无需重启。停用布局会释放该组合，冲突时保留原组合并显示原因；卡片和这里的设置保持同步。")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(item: $editingAction) { action in
            ConfigurableShortcutEditor(
                hotkeyService: hotkeyService,
                action: action
            )
        }
        .onChange(of: hotkeyService.configurableHotkeyStates) { oldStates, newStates in
            for action in ConfigurableHotkeyAction.allCases where oldStates[action] != newStates[action] {
                guard let state = newStates[action] else { continue }
                switch state {
                case .active, .disabled:
                    actionFailureMessages[action] = nil
                default:
                    break
                }
            }
        }
    }

    private func shortcutGroup(
        _ title: String,
        actions: [ConfigurableHotkeyAction],
        isExpanded: Binding<Bool>,
        identifier: String
    ) -> some View {
        let attentionCount = actions.filter { configurableShortcutStatus($0).needsAttention }.count
        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(spacing: NarcSpacing.xs) {
                ForEach(actions) { action in
                    configurableShortcutRow(action)
                    if action != actions.last {
                        Divider()
                    }
                }
            }
            .padding(.top, NarcSpacing.sm)
        } label: {
            HStack(spacing: NarcSpacing.sm) {
                Text(title)
                    .font(.narcSubtitle)
                Text("\(actions.count) 项")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                Spacer(minLength: NarcSpacing.sm)
                if attentionCount > 0 {
                    Label("\(attentionCount) 项需处理", systemImage: "exclamationmark.triangle.fill")
                        .font(.narcCaption)
                        .foregroundColor(.narcWarn)
                }
            }
            .padding(.vertical, NarcSpacing.xs)
        }
        .accessibilityIdentifier(identifier)
    }

    private func configurableShortcutRow(_ action: ConfigurableHotkeyAction) -> some View {
        let status = configurableShortcutStatus(action)
        return VStack(alignment: .leading, spacing: NarcSpacing.xs) {
            HStack(spacing: NarcSpacing.sm) {
                VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                    Text(action.title).font(.narcBody)
                    Label(status.message, systemImage: status.symbolName)
                        .font(.narcCaption)
                        .foregroundColor(status.color)
                }
                Spacer(minLength: NarcSpacing.sm)
                ShortcutBadge(label: status.shortcut.displayLabel)
                if action.supportsEnabledToggle {
                    Toggle(
                        "启用",
                        isOn: Binding(
                            get: { hotkeyService.isEnabled(for: action) },
                            set: { enabled in
                                let result = hotkeyService.setEnabled(enabled, for: action)
                                recordResult(result, for: action)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("启用\(action.title)")
                }
                Button("修改…") { editingAction = action }
                    .disabled(DevRuntimeOptions.noAX && action.requiresAccessibility)
                    .accessibilityLabel("修改\(action.title)快捷键")
                Button {
                    let result = hotkeyService.updateShortcut(action.defaultShortcut, for: action)
                    recordResult(result, for: action)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled((DevRuntimeOptions.noAX && action.requiresAccessibility) || isDefaultActive(action))
                .help("恢复默认：\(action.defaultShortcut.displayLabel)")
                .accessibilityLabel("恢复\(action.title)默认快捷键")
            }
            if let detailMessage = status.detailMessage {
                Text(detailMessage)
                    .font(.narcCaption)
                    .foregroundColor(status.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, NarcSpacing.xs)
    }

    private func isDefaultActive(_ action: ConfigurableHotkeyAction) -> Bool {
        hotkeyService.shortcut(for: action) == action.defaultShortcut
    }

    private func recordResult(_ result: ConfigurableShortcutUpdateResult, for action: ConfigurableHotkeyAction) {
        if case .rejected(let reason) = result {
            actionFailureMessages[action] = reason.userMessage
        } else {
            actionFailureMessages[action] = nil
        }
    }

    private func configurableShortcutStatus(_ action: ConfigurableHotkeyAction) -> ShortcutStatusPresentation {
        ShortcutStatusPresentation(
            configuredShortcut: hotkeyService.shortcut(for: action),
            state: hotkeyService.hotkeyState(for: action),
            isRuntimeUnavailable: DevRuntimeOptions.noAX && action.requiresAccessibility,
            operationFailure: actionFailureMessages[action]
        )
    }
}

/// Editing stays local until Apply so partially chosen chords never become
/// global registrations or take input away from the settings form.
private struct LegacyConfigurableShortcutEditor: View {
    @ObservedObject var hotkeyService: HotkeyService
    let action: ConfigurableHotkeyAction
    @Environment(\.dismiss) private var dismiss
    @State private var keyCode: UInt32
    @State private var modifiers: UInt32
    @State private var failureMessage: String?

    init(hotkeyService: HotkeyService, action: ConfigurableHotkeyAction) {
        self.hotkeyService = hotkeyService
        self.action = action
        let current = hotkeyService.shortcut(for: action)
        _keyCode = State(initialValue: current.keyCode)
        _modifiers = State(initialValue: current.modifiers)
    }

    private var candidate: ConfigurableShortcut {
        ConfigurableShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private func modifierBinding(_ flag: UInt32) -> Binding<Bool> {
        Binding(
            get: { modifiers & flag != 0 },
            set: { enabled in
                if enabled { modifiers |= flag } else { modifiers &= ~flag }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.lg) {
            Text(action.title).font(.narcSubtitle)
            Text("当前：\(hotkeyService.shortcut(for: action).displayLabel)")
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)

            VStack(alignment: .leading, spacing: NarcSpacing.sm) {
                Text("修饰键").font(.narcBody)
                HStack(spacing: NarcSpacing.md) {
                    Toggle("⌃ Control", isOn: modifierBinding(UInt32(controlKey)))
                    Toggle("⌥ Option", isOn: modifierBinding(UInt32(optionKey)))
                    Toggle("⇧ Shift", isOn: modifierBinding(UInt32(shiftKey)))
                    Toggle("⌘ Command", isOn: modifierBinding(UInt32(cmdKey)))
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                Text("主键").font(.narcBody)
                Picker("主键", selection: $keyCode) {
                    ForEach(ConfigurableShortcut.keyOptions) { key in
                        Text(key.label).tag(key.keyCode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
                Spacer()
                ShortcutBadge(label: candidate.displayLabel)
            }

            Text("至少选择两个修饰键。字母按标准键位显示；点击应用后立即生效，不改变窗口布局快捷键。")
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let failureMessage {
                Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.narcCaption)
                    .foregroundColor(.narcWarn)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shortcut-edit-error")
            }

            HStack {
                Button("使用默认组合") {
                    keyCode = action.defaultShortcut.keyCode
                    modifiers = action.defaultShortcut.modifiers
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("应用") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!candidate.isValid || DevRuntimeOptions.noAX)
            }
        }
        .padding(NarcSpacing.xl)
        .frame(width: 500)
        .onChange(of: candidate) { _, _ in failureMessage = nil }
    }

    private func apply() {
        _ = hotkeyService.updateShortcut(candidate, for: action)
        switch hotkeyService.hotkeyState(for: action) {
        case .active(let active) where active == candidate:
            dismiss()
        case .rejected(_, _, let reason), .unavailable(_, let reason):
            failureMessage = "\(reason.userMessage)。原设置未改变，请换一个组合。"
        default:
            failureMessage = "快捷键尚未生效，请稍后重试。"
        }
    }
}

/// Keep the displayed chord and its registration meaning together. In the
/// normal state the chord belongs only in the badge, not in a second label.
struct ShortcutStatusPresentation {
    let shortcut: ConfigurableShortcut
    let symbolName: String
    let message: String
    let detailMessage: String?
    let color: Color
    let needsAttention: Bool

    init(
        configuredShortcut: ConfigurableShortcut,
        state: ConfigurableHotkeyState,
        isRuntimeUnavailable: Bool = false,
        operationFailure: String? = nil
    ) {
        let shortcut: ConfigurableShortcut
        var symbolName: String
        var message: String
        var detailMessage: String? = nil
        var color: Color
        var needsAttention: Bool

        if isRuntimeUnavailable {
            shortcut = configuredShortcut
            symbolName = "hammer.fill"
            message = "未启用"
            detailMessage = "开发 no-AX 模式未注册此快捷键。"
            color = .narcTextMuted
            needsAttention = true
        } else {
            switch state {
            case .notRegistered:
                shortcut = configuredShortcut
                symbolName = "clock"
                message = "等待注册"
                color = .narcTextMuted
                needsAttention = true
            case .active(let active):
                shortcut = active
                symbolName = "checkmark.circle.fill"
                message = "已启用"
                color = .narcSuccess
                needsAttention = false
            case .disabled(let disabled):
                shortcut = disabled
                symbolName = "pause.circle.fill"
                message = "已停用"
                color = .narcTextMuted
                needsAttention = false
            case .rejected(let active, let requested, let reason):
                shortcut = active
                symbolName = "exclamationmark.triangle.fill"
                message = "原组合仍生效"
                detailMessage = "\(requested.displayLabel) 未生效：\(reason.userMessage)。"
                color = .narcWarn
                needsAttention = true
            case .unavailable(let requested, let reason):
                shortcut = requested
                symbolName = "xmark.circle.fill"
                message = "未启用"
                detailMessage = reason.userMessage
                color = .narcDanger
                needsAttention = true
            }
        }

        // Enabling a disabled layout can fail without changing its runtime
        // state. Keep that local error visible, including in a closed group,
        // but do not repeat a reason already carried by the shared state.
        if let operationFailure, detailMessage?.contains(operationFailure) != true {
            detailMessage = [detailMessage, operationFailure].compactMap { $0 }.joined(separator: " ")
            symbolName = "exclamationmark.triangle.fill"
            color = .narcWarn
            needsAttention = true
            if !isRuntimeUnavailable, case .active = state {
                message = "原组合仍生效"
            }
        }

        self.shortcut = shortcut
        self.symbolName = symbolName
        self.message = message
        self.detailMessage = detailMessage
        self.color = color
        self.needsAttention = needsAttention
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
