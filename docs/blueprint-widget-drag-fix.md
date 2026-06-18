# Blueprint: 悬浮窗拖拽方形灰底修复（#3）
- 对应 PRD: docs/PRD-workspace-ux-polish.md（#3）
- 蓝图状态: Confirmed
- 目标执行方: 🔵 弱模型
- 技术栈: Swift 5 / SwiftUI

## 🩻 根因（强模型分析）
悬浮窗本体是透明圆（`FloatingWidgetWindow` 已 `isOpaque=false / backgroundColor=.clear / hasShadow=false`）。
拖拽态下 `FloatingWidgetView.widget`（FloatingWidgetView.swift 80–126 行）对一个 `Circle().fill(.regularMaterial)` 施加了 `.scaleEffect(1.08)` + `.rotationEffect(-3°)`。
`.regularMaterial` 底层是 `NSVisualEffectView`（矩形），在 `rotationEffect`/`scaleEffect` 的图层变换下，其**矩形底板**会从圆形裁剪里穿帮 → 屏幕上出现方形灰块。这是 SwiftUI 材质 + 变换的已知合成问题。

## 🗂️ 文件级实现规划

### `NARC/Sources/Views/FloatingWidgetView.swift`（修改 `FloatingWidgetView.widget`）
职责：让变换作用在"已经是圆形"的扁平化图层上，杜绝矩形材质穿帮。

**首选修复 — 加 `.compositingGroup()`**：在内层 `.frame(width: 48, height: 48)`（当前 117 行）之后、`.scaleEffect`（118 行）之前插入一行：
```swift
.frame(width: floatingWidgetVisibleSize, height: floatingWidgetVisibleSize)
.compositingGroup()          // ← 新增：先把圆形 ZStack 扁平成一层，再做缩放/旋转
.scaleEffect(state == .dragging ? 1.08 : 1.0)
.rotationEffect(.degrees(state == .dragging ? -3 : 0))
```
`.compositingGroup()` 把 Circle+材质+overlay 先合成为单一（圆形）图层，旋转/缩放作用于该扁平结果，材质矩形底层不再独立参与变换 → 灰方块消失。

**兜底（仅当首选实测仍残留灰底时启用）— 拖拽态换纯色**：把根 `Circle().fill(.regularMaterial)`（88–90 行）改为拖拽时用不透明纯色，避开 vibrancy view：
```swift
Circle()
    .fill(state == .dragging
          ? AnyShapeStyle(Color(NSColor.windowBackgroundColor))
          : AnyShapeStyle(.regularMaterial))
```

| 改动 | 位置 | 边界 |
|------|------|------|
| 加 `.compositingGroup()` | `widget` 内层 frame 之后 | 不改尺寸/阴影/badge 逻辑 |
| （兜底）拖拽换纯色 | 根 Circle fill | 仅 `.dragging` 态替换，其它态保持材质 |

## 🔁 验证步骤（执行者必做）
1. `swift build` 通过。
2. 运行 app，拖动右下角悬浮窗：全程**只见圆形 + 轻微缩放/旋转，无方形灰块**；松手后无残影。
3. 若首选改法拖拽时仍有灰底 → 叠加"兜底"改法再验。

## 🚫 禁止项清单
- ❌ 不改 `FloatingWidgetWindow`（窗口层级/透明/hitTest 都是对的）。
- ❌ 不删 `.scaleEffect`/`.rotationEffect`/拖拽阴影（拖拽观感要保留）。
- ❌ 不改 idle/hasNotification 两态的视觉。
- ❌ 不引第三方库。

## ✅ 实现完成的判定
- [ ] 拖拽悬浮窗全过程无方形灰色底板，松手无残影。
- [ ] idle / hasNotification / dragging 三态其余视觉无回归。
- [ ] `swift build` 通过。

## 🧠 来自 Brain
- 相关历史：项目曾修过"圆角方块/方框 halo"（见 FloatingWidgetView/Window 注释），同源问题家族——透明窗口下矩形底层穿帮。本次是其拖拽变换变体。
