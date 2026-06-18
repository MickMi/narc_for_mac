# Blueprint: 智能复制气泡（#2）
- 对应 PRD: docs/PRD-workspace-ux-polish.md（#2）
- 蓝图状态: Confirmed
- 目标执行方: 🔵 弱模型
- 技术栈: Swift 5 / SwiftUI + AppKit + SwiftTerm

## 🧪 SwiftTerm 接口核实结论（强模型已验证，弱模型照用）
- ✅ `getSelection() -> String?`：public，取当前选中文本。
- ✅ `selectionActive: Bool`：public，是否有活跃选区。
- ✅ `selectionChanged(source: Terminal)`：**open**，可在 `NarcTerminalView` 重写以监听选区变化。
- ❌ `cellDimension` / `selection.start/end`：**internal**，跨模块拿不到 → **不要**尝试精确算选区矩形（会编译失败）。
- ➡️ 气泡定位用**最后一次鼠标抬起位置**（在 `NarcTerminalView` 自己的 `mouseUp` 里捕获），不依赖任何 internal API。

## 🗂️ 文件级实现规划

### `NARC/Sources/Views/TerminalPaneView.swift`（修改 `NarcTerminalView`）
职责：从"⌘⇧V 智能粘贴"翻转为"⌘⇧C / 点气泡 智能复制"，并管理选区气泡生命周期。

**改动 1 — `performKeyEquivalent`**（当前 29–39 行）：删除 ⌘⇧V 分支，改为拦截 ⌘⇧C：
```swift
override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isCmdShiftC = mods == [.command, .shift]
        && event.charactersIgnoringModifiers?.lowercased() == "c"
    if isCmdShiftC {
        performSmartCopy()
        return true
    }
    return super.performKeyEquivalent(with: event)
}
```

**改动 2 — 删除 `performSmartPaste()`（41–57 行），新增 `performSmartCopy()`**：
```swift
/// 取当前选区 → 去公共缩进 → 写系统剪贴板。⌘C 原始复制不受影响。
private func performSmartCopy() {
    guard let raw = getSelection(), !raw.isEmpty else { return }
    let dedented = NarcTerminalView.dedent(raw)
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(dedented, forType: .string)
    bubble?.showCopied()      // 反馈：气泡变"已复制"，~1s 后自动消失
}
```
> `dedent(_:)`（59–84 行）**保持不动**，复用。

**改动 3 — 捕获鼠标抬起位置 + 选区监听 + 气泡管理**（新增成员与重写）：
```swift
private var lastMouseUpInView: CGPoint = .zero
private weak var bubble: SmartCopyBubbleController?

override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)   // 先让 SwiftTerm 完成选区
    lastMouseUpInView = convert(event.locationInWindow, from: nil)
}

override func selectionChanged(source: Terminal) {
    super.selectionChanged(source: source)
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        if self.selectionActive, let s = self.getSelection(), !s.isEmpty {
            self.showOrMoveBubble(near: self.lastMouseUpInView)
        } else {
            self.dismissBubble()
        }
    }
}

override func resignFirstResponder() -> Bool {
    dismissBubble()
    return super.resignFirstResponder()
}

private func showOrMoveBubble(near point: CGPoint) {
    let ctrl = bubble ?? {
        let c = SmartCopyBubbleController(onCopy: { [weak self] in self?.performSmartCopy() })
        addSubview(c.view)
        bubble = c
        return c
    }()
    ctrl.position(near: point, in: bounds)   // 默认贴在点上方偏右，越界则钳制进 bounds
}

private func dismissBubble() {
    bubble?.view.removeFromSuperview()
    bubble = nil
}
```

| 函数 | 入参 | 出参 | 边界 |
|------|------|------|------|
| `performSmartCopy()` | 无 | Void | 无选区/空 → 直接 return，不动剪贴板 |
| `mouseUp(with:)` | `NSEvent` | Void | 必须先 `super` 再取坐标 |
| `selectionChanged(source:)` | `Terminal` | Void | 选区空/失活 → 关气泡；主线程更新 UI |
| `showOrMoveBubble(near:in:)` | `CGPoint` | Void | 越界钳制；已存在则只移动不重建 |

---

### `NARC/Sources/Views/SmartCopyBubble.swift`（新建）
职责：选区旁的小气泡。AppKit controller 持有一个 `NSHostingView` 包裹的 SwiftUI 气泡。
```swift
import SwiftUI
import AppKit

final class SmartCopyBubbleController {
    let view: NSView
    private let onCopy: () -> Void
    private let model = SmartCopyBubbleModel()

    init(onCopy: @escaping () -> Void) {
        self.onCopy = onCopy
        let host = NSHostingView(rootView: SmartCopyBubbleView(model: model, onTap: onCopy))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        host.frame = CGRect(x: 0, y: 0, width: 132, height: 30)
        self.view = host
    }

    /// 贴在 point 上方偏右，钳制进 container bounds（留 6pt 边距）。
    func position(near point: CGPoint, in container: CGRect) {
        var x = point.x + 8
        var y = point.y + 8            // NarcTerminalView 坐标系 y 向上
        x = min(max(6, x), container.maxX - view.frame.width - 6)
        y = min(max(6, y), container.maxY - view.frame.height - 6)
        view.setFrameOrigin(CGPoint(x: x, y: y))
    }

    /// 复制成功反馈：切到"已复制"，1s 后请求父视图移除（父视图通过 model 回调感知）。
    func showCopied() {
        model.copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.view.removeFromSuperview()
        }
    }
}

final class SmartCopyBubbleModel: ObservableObject {
    @Published var copied = false
}

struct SmartCopyBubbleView: View {
    @ObservedObject var model: SmartCopyBubbleModel
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: NarcSpacing.xs) {
                Image(systemName: model.copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                Text(model.copied ? "已复制" : "智能复制")
                    .font(.narcCaption)
                Text("⌘⇧C")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, NarcSpacing.sm)
            .padding(.vertical, NarcSpacing.xs)
            .background(Capsule().fill(model.copied ? Color.narcSuccess : Color.narcAccent))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}
```

---

### `NARC/Sources/Views/DashboardView.swift`（修改）
职责：移除右上角"智能粘贴"提示条。
- 删除 `smartPasteHint`（91–108 行）整个计算属性。
- 删除 toolbar 中对 `smartPasteHint` 的引用（69 行那一行）。

## 🚫 禁止项清单
- ❌ 不要碰 `dedent(_:)` 的算法。
- ❌ 不要拦截/改写 ⌘C（原始复制必须保留）。
- ❌ 不要尝试访问 `cellDimension` / `selection.start/end`（internal，编译不过）。
- ❌ 气泡不要做成独立 NSPanel/NSWindow（用 `NarcTerminalView` 的 subview，随终端走）。
- ❌ 不引第三方库。
- ❌ 不改终端渲染、PTY、env、focus 逻辑。

## ✅ 实现完成的判定
- [ ] 选中非空文本 → 气泡浮现在选区附近；选区清空/失焦 → 气泡消失。
- [ ] 点气泡 或 ⌘⇧C → 剪贴板内容已去公共缩进；⌘C 仍是原始复制（带缩进）。
- [ ] 复制后气泡显示"已复制"，约 1s 后消失。
- [ ] 右上角"智能粘贴"提示条已移除；⌘⇧V 不再触发智能粘贴。
- [ ] `swift build` 通过。

## 🧠 来自 Brain
- `brain-search` 无相关命中。
