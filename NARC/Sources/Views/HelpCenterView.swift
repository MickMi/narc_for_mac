import AppKit
import SwiftUI

enum HelpDestination {
    case todo, ai, bing, windowPicker, windows, replies, messages, shortcuts, aiSettings, repliesSettings
}

/// Independent chapters retain the persisted identifiers used by first-use hints.
enum HelpTopic: String, CaseIterable, Identifiable {
    case todo, ai, web, windows, layouts, replies, messages, shortcuts
    var id: Self { self }
    var firstUseHint: String {
        switch self {
        case .todo: return "写下要做的事，按 Return 添加。"
        case .ai: return "配置 Key 后可提问，支持联网和截图。"
        case .web: return "网页搜索无需 AI Key；点击结果会用默认浏览器打开。"
        case .windows: return "先标记常用窗口，再用快捷键召回。"
        case .layouts: return "选中窗口，用快捷键排列。"
        case .replies: return "这里接收 Codex 任务的回复提醒，首次使用需在设置中连接。"
        case .messages: return "这里显示应用提供的未读数字，不读取聊天内容。"
        case .shortcuts: return "快捷键可在设置中修改，无需一次记住。"
        }
    }
    var title: String {
        switch self {
        case .todo: return "随手记待办"
        case .ai: return "问 AI"
        case .web: return "搜索网页"
        case .windows: return "标记与召回"
        case .layouts: return "排列窗口"
        case .replies: return "Codex 回复提醒"
        case .messages: return "应用未读"
        case .shortcuts: return "快捷键与入口"
        }
    }
    var heading: String { self == .windows ? "先标记，再召回" : title }
    var icon: String {
        switch self {
        case .todo: return "checkmark.circle"
        case .ai: return "sparkles"
        case .web: return "magnifyingglass"
        case .windows: return "pin"
        case .layouts: return "macwindow"
        case .replies: return "bubble.left.and.bubble.right"
        case .messages: return "bell.badge"
        case .shortcuts: return "keyboard"
        }
    }
    var action: (String, HelpDestination) {
        switch self {
        case .todo: return ("打开待办", .todo)
        case .ai: return ("开始提问", .ai)
        case .web: return ("打开网页搜索", .bing)
        case .windows: return ("打开召回列表", .windowPicker)
        case .layouts: return ("查看窗口工具", .windows)
        case .replies: return ("查看回复", .replies)
        case .messages: return ("查看应用未读", .messages)
        case .shortcuts: return ("查看我的快捷键", .shortcuts)
        }
    }
    var lessons: [HelpLesson] {
        switch self {
        case .windows:
            return [
                HelpLesson("先标记要记住的窗口", "点击要标记的窗口，按：", shortcut: .toggleCurrentWindowPin, image: .markResult),
                HelpLesson("再召回刚才的窗口", "切到其他应用，按：", shortcut: .pinnedWindowSwitcher,
                           detail: "点击目标窗口，或按它前面的数字。", result: "原窗口回到前面，继续刚才的工作", image: .pins)
            ]
        case .todo:
            return [
                HelpLesson("记下一件事", "按快捷键打开待办：", shortcut: .quickCapture, detail: "输入待办，按 Return 添加。", image: .todo),
                HelpLesson("做完就勾掉", "点击待办前的圆圈完成；点铅笔修改内容。"),
                HelpLesson("选中文字直接记", "在其他应用选中文字，按：", shortcut: .selectedTextTodo, result: "选中文字成为一条待办")
            ]
        case .ai:
            return [
                HelpLesson("配置 DeepSeek", "在 AI 设置填写 API Key，点击保存。", detail: "已有密钥时，点击「授权读取密钥」。", image: .aiSettings),
                HelpLesson("提问，再接着问", "按快捷键打开问 AI：", shortcut: .askAI,
                           detail: "输入问题，点击发送或按 ⌘Return；可继续追问。\n保存本次对话：全部文字回合。\n复制本轮回答：最新一条回答。", image: .ai),
                HelpLesson("用截图提问", "在输入框按 ⌘V 粘贴图片，也可点回形针上传。", detail: "切到图片问答后发送；回答完成后，图片自动清空。", image: .aiImage),
                HelpLesson("查最新信息", "打开输入框内的「联网」开关，再发送问题。", detail: "联网默认开启，使用 DeepSeek Pro；图片问答使用 Flash。")
            ]
        case .web:
            return [
                HelpLesson("搜索网页", "按快捷键打开 Bing：", shortcut: .webSearch, detail: "输入关键词，按 Return 搜索；顶部可切换 Google。", image: .web),
                HelpLesson("在浏览器阅读", "点击结果，用系统默认浏览器打开。"),
                HelpLesson("直接打开 Google", "按：", shortcut: .googleSearch)
            ]
        case .layouts:
            return [
                HelpLesson("排列当前窗口", "点击目标窗口，再按左半屏快捷键：", shortcut: .layoutLeftHalf, image: .layouts),
                HelpLesson("换个位置", "在快捷键设置查看右半屏、居中和其他排列方式。"),
                HelpLesson("修改排列按键", "打开窗口工具，点击卡片里的快捷键修改；开关控制启停。")
            ]
        case .replies:
            return [
                HelpLesson("连接 Codex", "打开回复提醒设置，点击连接。按页面提示重启客户端。"),
                HelpLesson("收到回复后继续", "点击「继续对话」，回到对应 Codex 任务。", image: .replies),
                HelpLesson("稍后再看", "提示收起后，从 NARC 的「AI 回复」页找回；点击展开查看已有回合内容。")
            ]
        case .messages:
            return [
                HelpLesson("选择关注的应用", "打开设置的「通知」，勾选要监控的应用。"),
                HelpLesson("查看未读", "在「消息」页查看未读数字，点击应用即可打开。", detail: "「?」表示暂时无法确认未读数。", image: .messages)
            ]
        case .shortcuts:
            return [
                HelpLesson("随时打开 NARC", "点击桌面或菜单栏的 N，也可以按：", shortcut: .summonWidget),
                HelpLesson("改成顺手的组合", "打开快捷键设置，点击要修改的组合，选择按键并保存。", image: .shortcuts),
                HelpLesson("再找这份指南", "从面板的「更多」或右键 N，打开「帮助与指南」。")
            ]
        }
    }
}

struct HelpLesson {
    let title: String
    let instruction: String
    let shortcut: ConfigurableHotkeyAction?
    let detail: String?
    let result: String?
    let image: HelpTutorialAsset?
    init(_ title: String, _ instruction: String, shortcut: ConfigurableHotkeyAction? = nil,
         detail: String? = nil, result: String? = nil, image: HelpTutorialAsset? = nil) {
        self.title = title; self.instruction = instruction; self.shortcut = shortcut
        self.detail = detail; self.result = result; self.image = image
    }
}

/// Packaged screenshots of production components using isolated example data.
enum HelpTutorialAsset: String, CaseIterable, Identifiable {
    case markResult = "mark-result", pins, todo, layouts, shortcuts, aiSettings = "ai-settings", ai, aiImage = "ai-image", web, replies, messages
    var id: Self { self }
    func url(dark: Bool, applicationBundle: Bundle = .main) -> URL? {
        // build-app.sh embeds the SwiftPM bundle in Contents/Resources.
        let installed = applicationBundle.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("NARC_NARC.bundle"))
        }
        return (installed ?? Bundle.module).url(forResource: "tutorial-\(rawValue)-\(dark ? "dark" : "light")", withExtension: "png")
    }
    var title: String {
        switch self {
        case .markResult: return "窗口已标记"
        case .pins: return "已标记窗口列表"
        case .todo: return "待办"
        case .layouts: return "窗口排列设置"
        case .shortcuts: return "快捷键设置"
        case .aiSettings: return "DeepSeek 设置"
        case .ai: return "AI 提问与回答"
        case .aiImage: return "图片提问"
        case .web: return "网页搜索"
        case .replies: return "Codex 回复提醒"
        case .messages: return "应用未读"
        }
    }
}

final class HelpCenterNavigation: ObservableObject {
    @Published var selectedTopic: HelpTopic
    @Published var expandedImage: HelpTutorialAsset?
    init(_ topic: HelpTopic = .todo) { selectedTopic = topic }
}

struct HelpCenterView: View {
    @StateObject private var navigation: HelpCenterNavigation
    @ObservedObject private var hotkeys: HotkeyService
    @Environment(\.colorScheme) private var colorScheme
    @State private var showWindowDetails = false
    private var selection: HelpTopic { navigation.selectedTopic }
    let onOpen: (HelpDestination) -> Void

    init(initialTopic: HelpTopic = .todo, navigation: HelpCenterNavigation? = nil,
         hotkeyService: HotkeyService, onOpen: @escaping (HelpDestination) -> Void) {
        _navigation = StateObject(wrappedValue: navigation ?? HelpCenterNavigation(initialTopic))
        hotkeys = hotkeyService
        self.onOpen = onOpen
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("帮助与指南").font(.system(size: 18, weight: .semibold)).padding(.bottom, 22)
                ForEach(HelpTopic.allCases) { topic in
                    Button {
                        navigation.selectedTopic = topic
                        showWindowDetails = false
                    } label: {
                        Label(topic.title, systemImage: topic.icon)
                            .font(.system(size: 12, weight: selection == topic ? .semibold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 11)
                            .foregroundStyle(selection == topic ? Color.narcAccent : Color.narcText)
                            .background(selection == topic ? Color.narcAccent.opacity(0.09) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == topic ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(18).frame(width: 180).background(Color.narcFocusSurface)
            Divider()
            GeometryReader { geometry in
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(selection.heading).font(.system(size: 25, weight: .semibold)).id("help-top")
                            ForEach(Array(selection.lessons.enumerated()), id: \.offset) { index, lesson in
                                if index > 0 { Divider() }
                                lessonRow(lesson, number: index + 1, wide: geometry.size.width >= 680)
                            }
                            if selection == .windows { windowDetails }
                            Divider()
                            actions
                        }
                        .padding(26).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: selection) { _, _ in scroll.scrollTo("help-top", anchor: .top) }
                }
            }
        }
        .foregroundStyle(Color.narcText).background(Color.narcBackground)
        .frame(minWidth: 800, minHeight: 560)
        .sheet(item: $navigation.expandedImage) { asset in
            HelpTutorialImagePreview(asset: asset)
        }
        .onChange(of: selection) { _, _ in
            navigation.expandedImage = nil
            showWindowDetails = false
        }
    }

    private func lessonRow(_ lesson: HelpLesson, number: Int, wide: Bool) -> some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
        return layout {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("\(number)").font(.system(size: 12, weight: .semibold))
                        .frame(width: 25, height: 25).foregroundStyle(Color.narcAccent)
                        .background(Color.narcAccent.opacity(0.09)).clipShape(Circle())
                    Text(lesson.title).font(.system(size: 17, weight: .semibold))
                }
                Text(lesson.instruction).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                if let action = lesson.shortcut { shortcut(action) }
                if let detail = lesson.detail {
                    Text(detail).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                if let result = lesson.result {
                    Label(result, systemImage: "checkmark.circle").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.narcAccent).fixedSize(horizontal: false, vertical: true)
                }
            }.lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
            if let asset = lesson.image {
                Button { navigation.expandedImage = asset } label: {
                    if let url = asset.url(dark: colorScheme == .dark), let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.narcBorder.opacity(0.5), lineWidth: 0.5))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: wide ? 326 : 350)
                .help("放大图片")
                .accessibilityLabel("放大\(asset.title)示例")
            }
        }
    }

    @ViewBuilder private func shortcut(_ action: ConfigurableHotkeyAction) -> some View {
        if let active = hotkeys.activeShortcut(for: action) {
            let names = ["⌃": "⌃ Control", "⌥": "⌥ Option", "⇧": "⇧ Shift", "⌘": "⌘ Command"]
            let modifiers = active.displayLabel.prefix { names[String($0)] != nil }
            let caps = modifiers.map { names[String($0)]! } + [String(active.displayLabel.dropFirst(modifiers.count))]
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in keycap(cap) }
                }
                keycap(active.displayLabel)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(action.title)：\(active.displayLabel)")
        } else {
            Button("快捷键暂不可用 · 前往设置") { onOpen(.shortcuts) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.narcAccent)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
    }

    private func keycap(_ label: String) -> some View {
        Text(label).font(.system(size: 12, weight: .medium, design: .monospaced))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(Color.narcSurfaceMuted).clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var windowDetails: some View {
        DisclosureGroup("快捷直达与保留", isExpanded: $showWindowDetails) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("直达列表第 1 个窗口").font(.narcBody)
                    shortcut(.pinnedWindowSlot1)
                }
                Text("点击图钉，重启 NARC 后保留标记；用上下箭头调整编号。")
                Text("取消标记：选中原窗口，再按标记键。")
            }.font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
        }
        .font(.system(size: 13, weight: .medium)).tint(Color.narcAccent)
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button { onOpen(.shortcuts) } label: {
                Text("查看快捷键设置").lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }.buttonStyle(.plain).foregroundStyle(Color.narcTextMuted)
            Spacer(minLength: 0)
            if selection == .ai {
                Button("配置 AI") { onOpen(.aiSettings) }.buttonStyle(.bordered)
            } else if selection == .replies {
                Button("连接设置") { onOpen(.repliesSettings) }.buttonStyle(.bordered)
            }
            if selection != .shortcuts {
                Button { onOpen(selection.action.1) } label: {
                    Label(selection.action.0, systemImage: "arrow.up.right")
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }.buttonStyle(NarcFocusPrimaryButtonStyle())
            }
        }.font(.system(size: 13))
    }
}

struct HelpTutorialImagePreview: View {
    let asset: HelpTutorialAsset
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(asset.title).font(.narcSubtitle)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            if let url = asset.url(dark: colorScheme == .dark), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(24).frame(width: 680, height: 520)
            .foregroundStyle(Color.narcText).background(Color.narcBackground)
    }
}
