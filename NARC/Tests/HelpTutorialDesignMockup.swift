import AppKit
import SwiftUI
@testable import NARC

// Isolated design proposal only. This is not linked into the app.
enum TutorialDesignPage: String, CaseIterable { case mark, recall, direct, layouts, ai }
struct TutorialDesignMockup: View {
    let page: TutorialDesignPage
    let imageRoot: URL
    let appearance: String
    private var isPin: Bool { page == .mark || page == .recall || page == .direct }
    private var selected: String { isPin ? "标记与召回" : (page == .layouts ? "排列窗口" : "问 AI") }
    private var heading: String {
        if page == .mark { return "先标记，再召回" }
        if isPin { return "记住这个窗口，下次直接回来" }
        return page == .layouts ? "把当前窗口放到合适的位置" : "从第一问开始，接着问下去"
    }
    private var subtitle: String {
        if isPin { return "标记的是某一个窗口，例如浏览器里的「产品设计参考」，不是整个应用。" }
        return page == .layouts ? "排列用快捷键触发；窗口页里的卡片用于启停和修改组合。" : "文字、截图和联网都在同一处；先完成配置，再发出第一问。"
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NARC 使用指南 / \(selected)")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.narcTextMuted)
                    Text(heading).font(.system(size: 25, weight: .semibold))
                    if page != .mark { Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.narcTextMuted) }
                }
                if page == .mark {
                    markThenRecall
                } else {
                  stepStrip
                  HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        screenshot(isPin ? "pins" : (page == .layouts ? "layouts" : "ai"))
                            .frame(width: 350)
                    }.frame(width: 350)
                    instruction.frame(maxWidth: .infinity, alignment: .leading)
                  }
                }
                Spacer(minLength: 0)
                Divider()
                HStack {
                    Button("查看快捷键设置") {}.buttonStyle(.plain).foregroundStyle(Color.narcTextMuted)
                    Spacer()
                    Button {} label: {
                        Label(page == .mark ? "了解快捷直达" : (page == .recall ? "打开召回器" : (page == .direct ? "查看我的快捷键" : (page == .layouts ? "查看窗口工具" : "开始提问"))), systemImage: page == .mark ? "arrow.right" : "arrow.up.right")
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }.buttonStyle(NarcFocusPrimaryButtonStyle())
                }.font(.narcBody)
            }
            .padding(26).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(Color.narcText).background(Color.narcBackground)
        .frame(width: 960, height: 720)
    }
    private var markThenRecall: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    sequenceHeading("1", "先标记要记住的窗口")
                    Text("点击要标记的窗口，按：")
                        .fixedSize(horizontal: false, vertical: true)
                    keycaps("M")
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    screenshot("mark-result")
                }.frame(width: 326).padding(.top, 7)
            }
            Divider()
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    sequenceHeading("2", "再召回刚才的窗口")
                    Text("切到其他应用，按：")
                        .fixedSize(horizontal: false, vertical: true)
                    keycaps("P")
                    Text("点击「产品设计参考」，或按 1。")
                        .fixedSize(horizontal: false, vertical: true)
                    Label("原窗口回到前面，继续刚才的工作", systemImage: "checkmark.circle")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.narcAccent)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    screenshot("pins")
                }.frame(width: 326).padding(.top, 7)
            }
        }.font(.system(size: 12)).lineSpacing(4)
    }
    private func sequenceHeading(_ number: String, _ text: String) -> some View {
        HStack(spacing: 9) {
            Text(number).font(.system(size: 12, weight: .semibold))
                .frame(width: 25, height: 25).foregroundStyle(Color.narcAccent)
                .background(Color.narcAccent.opacity(0.09)).clipShape(Circle())
            Text(text).font(.system(size: 17, weight: .semibold))
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("帮助与指南").font(.system(size: 18, weight: .semibold)).padding(.bottom, 5)
            Text("选一项，照着做。")
                .font(.narcCaption).foregroundStyle(Color.narcTextMuted).padding(.bottom, 22)
            ForEach([("随手记待办","checkmark.circle"),("问 AI","sparkles"),("搜索网页","magnifyingglass"),("标记与召回","pin"),("排列窗口","macwindow"),("Codex 回复提醒","bubble.left.and.bubble.right"),("应用未读","bell.badge"),("快捷键与入口","keyboard")], id: \.0) { title,icon in
                Label(title,systemImage: icon).font(.system(size: 12, weight: selected == title ? .semibold : .regular))
                    .foregroundStyle(selected == title ? Color.narcAccent : Color.narcText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal,10).padding(.vertical,11)
                    .background(selected == title ? Color.narcAccent.opacity(0.09) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
        }
        .padding(18).frame(width: 180).frame(maxHeight: .infinity).background(Color.narcFocusSurface)
    }
    private var stepStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array((isPin ? ["标记窗口","从列表召回","快捷直达"] : (page == .layouts ? ["排列当前窗口","修改布局快捷键"] : ["配置与授权","提问与追问","图片与联网"])).enumerated()), id: \.offset) { index,title in
                let active = isPin ? index == (page == .mark ? 0 : (page == .recall ? 1 : 2)) : index == (page == .layouts ? 0 : 1)
                HStack(spacing: 6) {
                    Text("\(index+1)").font(.system(size: 10, weight: .semibold)).frame(width: 18,height: 18)
                        .background(active ? Color.narcAccent : Color.narcSurfaceMuted)
                        .foregroundStyle(active ? Color.white : Color.narcTextMuted).clipShape(Circle())
                    Text(title).font(.system(size: 12, weight: active ? .medium : .regular))
                }
                .padding(.horizontal,10).padding(.vertical,7)
                .foregroundStyle(active ? Color.narcAccent : Color.narcTextMuted)
                .background(active ? Color.narcAccent.opacity(0.06) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Spacer(minLength: 0)
        }
    }
    @ViewBuilder private var instruction: some View {
        VStack(alignment: .leading, spacing: 15) {
            if page == .recall {
                Text("打开列表，再选你要的窗口").font(.system(size: 17, weight: .semibold))
                keycaps("P")
                Text("① 按召回键，出现左边的列表。\n\n② 要回到「产品设计参考」，直接按数字 1，或点击这一行。\n\n③ 窗口回到前面，就能继续刚才的工作。")
                result("列表内只按数字即可", detail: "不用同时按 Control 和 Option；按 Esc 只收起列表，不删除标记。")
            } else if page == .direct {
                Text("熟悉编号后，不用再开列表").font(.system(size: 17, weight: .semibold))
                keycaps("1")
                Text("这组全局快捷键直接召回列表第 1 个窗口。把最后的 1 换成 2，就召回第 2 个。列表内按数字、全局按组合键，是两种不同用法。")
                result("让标记保留到下次启动", detail: "点击左图每行右侧的图钉，开启长期保留；未固定的标记在退出 NARC 后清除。")
                Text("不再需要时：回到那个窗口，再按 ⌃⌥M 取消标记。它只移除标记，不关闭窗口。")
                    .foregroundStyle(Color.narcTextMuted)
            } else if page == .layouts {
                Text("点选目标窗口，再按布局键").font(.system(size: 17, weight: .semibold))
                keycaps("←")
                Text("这组键把当前窗口放到左半屏。\n\n同理，→ 是右半屏；↑ 是上半屏；↓ 是下半屏。")
                result("卡片是设置入口", detail: "左图中的开关控制启停；点击卡片上的快捷键是在改键，不是立即移动窗口。")
            } else {
                Text("输入问题，再发送").font(.system(size: 17, weight: .semibold))
                Text("① 点底部「问一个问题…」输入内容。\n\n② 点「发送」，或按 Command + Return。回答会逐步出现。\n\n③ 继续在同一输入框提问，AI 会结合前文回答。")
                result("两种保存范围", detail: "「保存本次对话」保留全部文字回合；「复制本轮回答」只复制最新一条回答。")
            }
        }
        .font(.system(size: 13)).lineSpacing(4)
    }
    private func keycaps(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                ForEach(["⌃ Control","⌥ Option",key], id: \.self) { value in
                    Text(value).font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal,9).padding(.vertical,8)
                        .background(Color.narcSurfaceMuted).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
    private func result(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading,spacing: 6) {
            Label(title,systemImage: "checkmark.circle").font(.system(size: 12,weight: .medium)).foregroundStyle(Color.narcAccent)
            Text(detail).font(.system(size: 12)).foregroundStyle(Color.narcTextMuted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity,alignment: .leading)
        .background(Color.narcAccent.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func screenshot(_ name: String) -> some View {
        Group {
            if let image = NSImage(contentsOf: imageRoot.appendingPathComponent("tutorial-\(name)-\(appearance).png")) {
                Image(nsImage:image).resizable().scaledToFit()
            } else { Text("截图待生成").foregroundStyle(Color.narcTextMuted) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.narcBorder.opacity(0.5),lineWidth: 0.5))
    }
}
