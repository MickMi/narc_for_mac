# Review: 智能复制(#2) + 拖拽灰底(#3) · 2026-06-18

## 📊 结论
- 审查范围：
  - #2：`NARC/Sources/Views/TerminalPaneView.swift`、`NARC/Sources/Views/SmartCopyBubble.swift`、`DashboardView.swift`（提示条移除）
  - #3：`NARC/Sources/Views/FloatingWidgetView.swift`
- 蓝图判定项：#3 全过；#2 大部分过，**1 项 Must Fix**
- 编译：`swift build` ✅
- 结论：
  - **#3 拖拽灰底：✅ 可合并**
  - **#2 智能复制：⚠️ 需修改后合并**（核心复制可用，但气泡反馈/清理被一个引用 bug 破坏）

---

## #3 拖拽灰底 — ✅ 通过
| 判定项 | 状态 | 证据 |
|--------|------|------|
| 加 `.compositingGroup()` 在 frame 之后、变换之前 | ✅ | FloatingWidgetView.swift:117-120，顺序正确 |
| 不删 scale/rotation/拖拽阴影 | ✅ | 119-125 保留 |
| 不改其它态视觉 | ✅ | 仅插入一行 |
| 编译通过 | ✅ | |
> 原理正确：先把圆形 ZStack 扁平成单层再做缩放/旋转，毛玻璃矩形底层不再独立参与变换 → 灰方块消除。运行时目测确认即可。

---

## #2 智能复制 — ⚠️ 需修改后合并

### 通过项
| 判定项 | 状态 | 证据 |
|--------|------|------|
| ⌘⇧C 触发智能复制，⌘C 不变 | ✅ | TerminalPaneView.swift:19-29 |
| dedent 复用、未改算法 | ✅ | 46-66 |
| selectionChanged 驱动气泡显隐 | ✅ | 85-95 |
| 鼠标抬起位置定位（不碰 internal API） | ✅ | 用 `addLocalMonitorForEvents(.leftMouseUp)` 取坐标，避开 internal cellDimension |
| 右上角"智能粘贴"提示条移除 | ✅ | DashboardView 已无 smartPasteHint |
| SmartCopyBubble.swift 新建 | ✅ | controller+model+view 结构 |

### 🚨 必须修复 (Must Fix)
| # | 问题 | 文件:行号 | 修复 |
|---|------|----------|------|
| 1 | **`bubble` 是 `weak`，但没有任何强引用持有 `SmartCopyBubbleController`** → controller 在 `showOrMoveBubble` 返回后立即被释放（只有它的 `view` 被 `addSubview` 持有，view 不反向持有 controller）。后果：① `performSmartCopy` 里 `bubble?.showCopied()` 时 bubble 已 nil → **"已复制"反馈和 1s 自动消失永不触发**；② `dismissBubble` 的 `bubble?.view.removeFromSuperview()` → bubble nil → **气泡永不移除**；③ 每次 `selectionChanged` 因 `bubble` 恒为 nil → `bubble ?? {…}` **每次都新建一个气泡 subview，永久堆叠**。复制本身能用，但气泡体验全坏。 | `TerminalPaneView.swift:16` | `private weak var bubble` → `private var bubble`（改成强引用）。dismissBubble 末尾补 `bubble = nil`（已有）即可正常释放 controller + 移除 view。 |

### ⚠️ 建议优化 (Should Fix)
| # | 问题 | 文件:行号 | 建议 |
|---|------|----------|------|
| 1 | 失焦/切 Tab 不消气泡：蓝图要求 `resignFirstResponder` 时 dismiss，未实现。选区清空有处理，但切到别的 Tab 时 SwiftTerm 选区可能保留，气泡留在隐藏 pane 上。 | TerminalPaneView.swift | 加 `override func resignFirstResponder() -> Bool { dismissBubble(); return super.resignFirstResponder() }` |
| 2 | `mouseMonitor` 仅在 window 变 nil 时移除；若重复进入有 window 的分支会叠加 monitor。 | TerminalPaneView.swift:72-83 | 添加前先 `if let m = mouseMonitor { NSEvent.removeMonitor(m) }` |

### 💡 可选 (Nice to Have)
- 气泡 Y 定位：若 SwiftTerm 视图是 flipped，气泡会出现在选区下方而非上方（纯视觉，跑一次确认即可）。

## 🚫 禁止项检查
- #2/#3 均未违反：未改 dedent / 未抢 ⌘C / 未碰 internal API / 未引第三方库 / 未改 computedState / 拖拽态视觉保留。✅

## ✅ 复审清单（修完对照）
- [ ] `bubble` 改强引用后：选中→出气泡；再选别处→旧气泡消失不堆叠；点气泡/⌘⇧C→剪贴板去缩进 + 气泡显示"已复制"约 1s 后消失。
- [ ] 切 Tab/失焦后气泡消失（若采纳 Should-Fix 1）。
- [ ] `swift build` 通过。
