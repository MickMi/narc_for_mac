import SwiftUI

/// Preferences window with tabbed navigation.
struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            MonitoringPreferencesView()
                .tabItem {
                    Label("Monitoring", systemImage: "eye")
                }

            ShortcutsPreferencesView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            FiltersPreferencesView()
                .tabItem {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - General Tab

struct GeneralPreferencesView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showFloatingWidget") private var showFloatingWidget = true
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("widgetSize") private var widgetSize = "Medium"

    private let sizeOptions = ["Small", "Medium", "Large"]

    var body: some View {
        Form {
            Section("System Behavior") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show floating widget", isOn: $showFloatingWidget)
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            }

            Section("Interface") {
                Picker("Widget size", selection: $widgetSize) {
                    ForEach(sizeOptions, id: \.self) { size in
                        Text(size).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Monitoring Tab

struct MonitoringPreferencesView: View {
    // In a real implementation, this would be bound to a shared data source
    @State private var apps: [MonitoredApp] = [
        MonitoredApp(id: "com.tencent.xinWeChat", displayName: "WeChat", category: .im, isEnabled: true),
        MonitoredApp(id: "com.tencent.WeWorkMac", displayName: "WeCom", category: .im, isEnabled: true),
        MonitoredApp(id: "com.electron.lark", displayName: "Lark", category: .im, isEnabled: true),
        MonitoredApp(id: "com.microsoft.VSCode", displayName: "VS Code", category: .ide, isEnabled: false),
    ]

    var body: some View {
        Form {
            Section("Monitored Applications") {
                ForEach($apps) { $app in
                    HStack {
                        // App icon
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "app.fill")
                                .frame(width: 24, height: 24)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading) {
                            Text(app.displayName)
                                .font(.system(size: 13, weight: .medium))
                            Text(app.id)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $app.isEnabled)
                            .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Shortcuts Tab

struct ShortcutsPreferencesView: View {
    var body: some View {
        Form {
            Section("Window Layout Shortcuts") {
                ForEach(WindowLayout.allCases) { layout in
                    HStack {
                        Image(systemName: layout.iconName)
                            .frame(width: 20)
                            .foregroundColor(.secondary)

                        Text(layout.rawValue)
                            .font(.system(size: 13))

                        Spacer()

                        Text(layout.hotkeyLabel)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Text("Shortcuts require Accessibility permission. Go to System Settings → Privacy & Security → Accessibility to grant access.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Filters Tab

struct FiltersPreferencesView: View {
    @State private var filters: [NotificationFilter] = []
    @State private var showingAddSheet = false

    // Available apps for filter targeting
    private let availableApps: [(id: String, name: String)] = [
        ("*", "All Apps"),
        ("com.tencent.xinWeChat", "WeChat"),
        ("com.tencent.WeWorkMac", "WeCom"),
        ("com.electron.lark", "Lark"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Filter list
            if filters.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No filter rules")
                        .font(.system(size: 14, weight: .medium))
                    Text("Add rules to customize which notifications are highlighted, silenced, or hidden.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filters) { filter in
                        FilterRuleRow(filter: filter, appName: appName(for: filter.appBundleID))
                    }
                    .onDelete { indexSet in
                        filters.remove(atOffsets: indexSet)
                        saveFilters()
                    }
                }
            }

            Divider()

            // Add button
            HStack {
                Button(action: { showingAddSheet = true }) {
                    Label("Add Rule", systemImage: "plus")
                }

                Spacer()

                Text("\(filters.count) rule(s)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFilters() }
        .sheet(isPresented: $showingAddSheet) {
            AddFilterSheet(availableApps: availableApps) { newFilter in
                filters.append(newFilter)
                saveFilters()
            }
        }
    }

    private func appName(for bundleID: String) -> String {
        availableApps.first(where: { $0.id == bundleID })?.name ?? bundleID
    }

    private func saveFilters() {
        if let data = try? JSONEncoder().encode(filters) {
            UserDefaults.standard.set(data, forKey: "narc.filters")
        }
    }

    private func loadFilters() {
        if let data = UserDefaults.standard.data(forKey: "narc.filters"),
           let saved = try? JSONDecoder().decode([NotificationFilter].self, from: data) {
            filters = saved
        }
    }
}

/// A single filter rule row in the preferences list.
struct FilterRuleRow: View {
    let filter: NotificationFilter
    let appName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(appName)
                        .font(.system(size: 13, weight: .medium))

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(filter.filterType.rawValue)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                if !filter.pattern.isEmpty {
                    Text("Pattern: \(filter.pattern)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action badge
            Text(filter.action.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(actionColor(filter.action))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(actionColor(filter.action).opacity(0.12))
                )

            // Enabled toggle
            Circle()
                .fill(filter.isEnabled ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
        }
    }

    private func actionColor(_ action: NotificationFilter.FilterAction) -> Color {
        switch action {
        case .highlight: return .orange
        case .normal: return .blue
        case .silent: return .gray
        case .hide: return .red
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
        VStack(spacing: 16) {
            Text("Add Filter Rule")
                .font(.system(size: 16, weight: .semibold))

            Form {
                Picker("App", selection: $selectedAppID) {
                    ForEach(availableApps, id: \.id) { app in
                        Text(app.name).tag(app.id)
                    }
                }

                Picker("Type", selection: $filterType) {
                    ForEach(NotificationFilter.FilterType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                if filterType == .badgeThreshold {
                    TextField("Badge threshold (e.g. 3)", text: $pattern)
                } else if filterType == .keyword {
                    TextField("Keyword to match", text: $pattern)
                }

                Picker("Action", selection: $action) {
                    ForEach(NotificationFilter.FilterAction.allCases, id: \.self) { act in
                        Text(act.rawValue).tag(act)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
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
        .padding(20)
        .frame(width: 400, height: 340)
    }
}
