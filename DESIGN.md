# NARC Dashboard · Visual Softening Design System

> **源文件：** `narc-dashboard-soft-v5-5.html`（高保真原型稿，最后一次对齐修正版）
> **版本：** v5.5
> **导出日期：** 2026-06-17
> **适用范围：** NARC macOS SwiftUI App 多终端工作台 Dashboard 视觉软化改版
> **设计方向：** 现代极简 (Modern Minimal)，系统蓝强调色，连续曲率圆角，分层柔和阴影

---

## 0. 设计目标

将原有「生硬直角圆角 + 几乎无阴影 + 偏紧间距」的 Dashboard 视觉，软化为更圆润、优雅、有分层呼吸感的 macOS 工作台界面。**布局骨架和交互逻辑不变**，只调整视觉层。

五个软化方向：
1. 圆角改为连续曲率观感，更大的半径阶梯
2. 选中/hover/卡片用柔和分层阴影 + 半透明材质 + 细描边
3. 放大留白，行更舒展但不松散
4. 标签页之间用间距替代可见分隔线
5. 需关注红态醒目但不破坏整体优雅

---

## 1. 颜色系统 (Color Tokens)

所有颜色使用 OKLch 色彩空间。浅色/深色双模适配。底层映射 macOS 系统语义色。

### 1.1 基础色板

| Token | 浅色 | 深色 | 用途 |
|-------|------|------|------|
| `--bg` | `oklch(97% 0.002 260)` | `oklch(18% 0.005 260)` | 窗口/页面背景 |
| `--surface` | `oklch(100% 0 0)` | `oklch(23% 0.005 260)` | 卡片/面板表面 |
| `--fg` | `oklch(20% 0.005 270)` | `oklch(95% 0.002 260)` | 主文字色 |
| `--muted` | `oklch(52% 0.01 270)` | `oklch(62% 0.01 260)` | 次要文字色 |
| `--border` | `oklch(88% 0.005 260)` | `oklch(30% 0.005 260)` | 描边/分隔线 |
| `--accent` | `oklch(58% 0.18 255)` | `oklch(65% 0.18 255)` | 系统蓝强调色 |

### 1.2 衍生色

| Token | 浅色 | 深色 | 用途 |
|-------|------|------|------|
| `--accent-soft` | `oklch(58% 0.05 255 / 0.10)` | `oklch(65% 0.06 255 / 0.15)` | 选中态背景 |
| `--fg-soft` | `oklch(20% 0.005 270 / 0.05)` | `oklch(95% 0.002 260 / 0.06)` | hover 态背景 |
| `--surface-raised` | `oklch(100% 0 0)` | `oklch(26% 0.005 260)` | 抬升表面 |

### 1.3 状态色

| Token | 浅色 | 深色 | 语义 |
|-------|------|------|------|
| `--green` | `oklch(55% 0.16 155)` | `oklch(62% 0.16 155)` | 等待输入 / 任务完成 |
| `--orange` | `oklch(62% 0.17 65)` | `oklch(68% 0.17 65)` | 警告（预留） |
| `--red` | `oklch(52% 0.20 25)` | `oklch(58% 0.20 25)` | 需审批 / 需关注 |
| `--gray` | `oklch(55% 0.01 270)` | `oklch(60% 0.01 270)` | 已结束 |

### 1.4 状态柔和底色（透明度底 + 对应色相）

| Token | 浅色（透明度） | 深色（透明度） | 用途 |
|-------|---------------|---------------|------|
| `--green-soft` | `oklch(55% 0.06 155 / 0.12)` | `oklch(62% 0.08 155 / 0.15)` | 等待输入/完成徽标底 |
| `--green-soft2` | `oklch(55% 0.04 155 / 0.08)` | `oklch(62% 0.05 155 / 0.10)` | 完成行 / 气泡底 |
| `--orange-soft` | `oklch(62% 0.06 65 / 0.12)` | `oklch(68% 0.08 65 / 0.15)` | 警告徽标底（预留） |
| `--red-soft` | `oklch(52% 0.06 25 / 0.10)` | `oklch(58% 0.08 25 / 0.12)` | 需关注行 / 徽标底 |
| `--gray-soft` | `oklch(55% 0.01 270 / 0.10)` | `oklch(60% 0.01 270 / 0.12)` | 已结束徽标底 |

### 1.5 SwiftUI 映射指南

```swift
// macOS 系统语义色（推荐优先使用）
Color(nsColor: .windowBackgroundColor)     // → --bg
Color(nsColor: .controlBackgroundColor)    // → --surface
Color(nsColor: .labelColor)                // → --fg
Color(nsColor: .secondaryLabelColor)       // → --muted
Color(nsColor: .separatorColor)            // → --border
Color(nsColor: .controlAccentColor)        // → --accent

// 状态色直接用系统色
Color(nsColor: .systemGreen)               // → --green （等待/完成）
Color(nsColor: .systemRed)                 // → --red   （需关注）
Color(nsColor: .systemGray)                // → --gray  （已结束）
```

---

## 2. 圆角阶梯 (Radius Scale)

采用比传统 macOS 更大的半径值，配合 `.continuous` 样式获得连续曲率（squircle）观感。

| Token | 值 | SwiftUI | 适用场景 |
|-------|----|---------|---------|
| `--radius-sm` | 6pt | `.continuous(6)` | 小按钮、操作图标按钮、状态点 |
| `--radius-md` | 10pt | `.continuous(10)` | **标签行**（核心）、输入框、小卡片 |
| `--radius-lg` | 14pt | `.continuous(14)` | 面板、**气泡卡片**、侧栏分组 |
| `--radius-xl` | 20pt | `.continuous(20)` | 窗口容器、主卡片 |
| `--radius-pill` | Capsule | `Capsule()` | **胶囊按钮**、状态徽标 |

> **关键决策：** 标签行使用 10pt 连续曲率圆角，比原来的 4-6pt 标准值更大。标签行之间用 2pt 间距替代可见分隔线，各行独立的圆角背景让 hover/选中时自然浮现。

---

## 3. 阴影层次 (Shadow Scale)

使用多层叠加阴影（near + mid + far）替代单一大阴影，营造自然柔和的分层感。

| Token | 浅色模式 | 深色模式 | SwiftUI 近似 | 适用场景 |
|-------|---------|---------|-------------|---------|
| `--shadow-xs` | `0 0.5px 1px rgba(0,0,0,.04)` | `0 0.5px 1px rgba(0,0,0,.30)` | `.shadow(radius: 0.5, y: 0.5)` | 极轻微抬升（按钮默认） |
| `--shadow-sm` | `0 0.5px 1.5px rgba(0,0,0,.05), 0 1px 2px rgba(0,0,0,.03)` | `0 0.5px 2px rgba(0,0,0,.40), 0 1px 3px rgba(0,0,0,.25)` | `.shadow(radius: 2, y: 1)` | **气泡卡片**、hover 浮起 |
| `--shadow-md` | `0 1px 3px rgba(0,0,0,.05), 0 3px 6px rgba(0,0,0,.04)` | `0 1px 4px rgba(0,0,0,.40), 0 4px 8px rgba(0,0,0,.30)` | `.shadow(radius: 4, y: 2)` | 弹出面板、卡片 |
| `--shadow-lg` | `0 2px 8px rgba(0,0,0,.05), 0 6px 16px rgba(0,0,0,.04), + 0.5px border` | 同上透明度 2-3× | `.shadow(radius: 8, y: 4)` | 模态弹窗 |
| `--shadow-xl` | `0 4px 12px rgba(0,0,0,.06), 0 12px 32px rgba(0,0,0,.05), + 0.5px border` | 同上透明度 2-3× | `.shadow(radius: 16, y: 8)` | 主窗口容器 |
| `--shadow-inner` | `inset 0 1px 2px rgba(0,0,0,.03)` | `inset 0 1px 2px rgba(255,255,255,.04)` | `.shadow(radius: 1, y: -1)` 或 overlay | 选中态内阴影 |

---

## 4. 间距体系 (Spacing Scale)

基于 8pt 网格，向上均匀扩展。

| Token | 值 | 适用场景 |
|-------|----|---------|
| `--space-1` | 4pt | 微调内边距、图标与文字间隙、徽标内部 padding |
| `--space-2` | 8pt | **标签行间距（替代分隔线）**、气泡内部元素间距、工具栏按钮间距 |
| `--space-3` | 12pt | 行内元素间距（状态点 ↔ 标题）、标签行水平 padding、工具栏元素间距、侧栏 label 内边距 |
| `--space-4` | 16pt | 面板内边距、气泡 padding、工具栏水平 padding |
| `--space-5` | 20pt | 区块间隙 |
| `--space-6` | 24pt | 大区块分隔 |
| `--space-8` | 32pt | 页面级 padding |
| `--space-10` | 40pt | 主要视觉分组 |
| `--space-12` | 48pt | 空状态大面积留白 |

> **关键决策：** 标签行之间的分隔不使用可见线，改为 `gap: 2pt`（`--space-2` 的 1/4 即 2px）+ 各行独立圆角背景。hover/选中时该行背景色浮现，自然形成视觉分界。

---

## 5. 字体系统 (Typography)

| Token | 字体栈 | 大小 | 用途 |
|-------|--------|------|------|
| `--font-display` | SF Pro Display, system-ui | - | 标题、标签行标题、区块标签 |
| `--font-body` | SF Pro Text, system-ui | - | 正文、标签行元信息 |
| `--font-mono` | SF Mono, ui-monospace | - | 路径、时间戳、代码、徽标 |
| `--fs-caption` | - | 11pt | 次要标注、徽标文字、侧栏 section label |
| `--fs-meta` | - | 12pt | 元信息（cwd 路径/时间）、气泡正文、按钮 |
| `--fs-body` | - | 13pt | **标签行标题**、正文、工具栏标题 |
| `--fs-h3` | - | 15pt | 子标题（预留） |
| `--fs-h2` | - | 20pt | 区块标题、空状态标题 |
| `--fs-h1` | - | 28pt | 主标题（预留） |

> **字重规则：** 标签行标题默认 Medium (500)，选中态 Semibold (600)。侧栏 section label 用 Semibold + 0.04em letter-spacing + uppercase。

---

## 6. 组件规格 (Component Specs)

### 6.1 工具栏 (Toolbar)

```
Height: 44pt
Padding: 0 16pt (horizontal)
Background: color-mix(bg 85%, transparent)
Backdrop: blur(20px) — macOS 毛玻璃效果
Bottom border: 0.5px hairline
```

**元素布局：**
```
[终端图标 20×20] [gap: 12pt] [标题 · N 个终端]  ←→  [主题切换胶囊] [gap: 8pt] [新建终端胶囊]
```

**主题切换按钮：**
- Height: 28pt（与新建按钮统一）
- Padding: 0 10pt
- Border: 0.5px hairline
- Border-radius: Capsule
- 图标 13×13 + 文字 "浅色" / "深色"

**新建终端按钮：**
- Height: 28pt（与主题切换统一）
- Padding: 0 14pt
- Border-radius: Capsule
- Background: accent 色实心
- 图标 12×12 (plus) + 文字 "新建终端"
- Hover: brightness(1.08) + shadow 微浮
- Active: scale(0.97)

### 6.2 侧栏 (Sidebar)

```
Width: 300pt (fixed)
Background: color-mix(bg 60%, surface)
Padding: 8pt (四周)
Gap between rows: 2pt
Scrollbar: 4pt wide, thumb = border color, track = transparent
```

### 6.3 侧栏分组标签 (Sidebar Section Label)

```
Font: display, 11pt, Semibold, 0.04em letter-spacing, uppercase
Color: muted
Padding: 12pt 12pt 4pt 12pt
Margin-top: 8pt
First-child margin-top: 0
```

### 6.4 标签行 (Tab Row) — 核心组件

**基础结构：**
```
[左侧指示条 3pt (条件)] [padding: 9pt 12pt] [状态点 7×7] [gap: 12pt] [标题 + 元信息] [← flex →] [状态徽标] [操作按钮]
```

**最小高度：** 46pt
**圆角：** 10pt (continuous)
**Border：** 1px transparent（占位，选中/需关注时有色）

#### 6.4.1 状态矩阵

| 状态 | 背景 | 边框 | 左侧指示条 | 阴影 | 标题字重 | 操作按钮 |
|------|------|------|-----------|------|---------|---------|
| **默认** | 透明 | 1px 透明 | 无 | 无 | 500 (Medium) | 隐藏 |
| **Hover** | `--fg-soft`（前景色 5%） | 透明 | 无 | 无 | 500 | 显示 |
| **选中** | `--accent-soft`（蓝色 10%） | 1px 半透明蓝 | **3pt 蓝色**，距上下 6pt | 内阴影 inset | 600 (Semibold) | 显示 |
| **需关注** | `--red-soft`（红色 10%） | 1px 半透明红 | **3pt 红色**，距上下 6pt | 无 | 500 | 显示 |
| **任务完成** | `--green-soft2`（绿色 8%） | 1px 半透明绿 | **3pt 绿色**，距上下 6pt | 无 | 500 | 显示 |

#### 6.4.2 左侧指示条
- 用 `::before` 伪元素实现
- Width: 3pt
- Top/Bottom: 6pt（与行上下边缘保持间距）
- Border-radius: 右侧 Capsule（`0 999px 999px 0`），远离行边缘的一端圆滑

#### 6.4.3 状态点 (Status Dot)

| 状态 | 颜色 | 特效 |
|------|------|------|
| 运行中 | accent (蓝) | `box-shadow: 0 0 4px accent-soft` |
| 等待输入 | green | `box-shadow: 0 0 4px green-soft` |
| 需审批 | red | `box-shadow: 0 0 4px red-soft` |
| 已结束 | gray | 无光晕 |
| 任务完成 | green | `box-shadow: 0 0 5px green-soft`；**脉冲动画** |

#### 6.4.4 任务完成脉冲动画
```css
@keyframes dotPulse {
  0%, 100% { box-shadow: 0 0 4px green-soft; }
  50%      { box-shadow: 0 0 10px green, 0 0 20px green-soft; }
}
/* 2s 循环，ease-out */
```

#### 6.4.5 状态徽标 (Status Badge)

```
Font: 10pt, Semibold, 0.02em letter-spacing
Padding: 2pt 8pt
Border-radius: Capsule
```

| 徽标文字 | 类名 | 背景色 | 文字色 |
|---------|------|--------|--------|
| 运行中 | `badge-running` | accent-soft | accent |
| 等待输入 | `badge-waiting` | green-soft | green |
| 需审批 | `badge-approval` | red-soft | red |
| 任务完成 | `badge-completed` | green-soft | green |
| 已结束 | `badge-ended` | gray-soft | gray |

#### 6.4.6 操作按钮 (Tab Actions)

```
Container: flex row, gap 4pt, opacity 0 → 1 on hover/selected/attention/completed
Button size: 24×24pt（v5.5 从 22×22 扩大，提升可点击区域）
Icon size: 13×13pt（v5.5 从 12px 增大）
Border-radius: 6pt (continuous)
Default color: muted
Hover background: fg-soft
Hover color: fg
Danger hover background: red-soft
Danger hover color: red
```

### 6.5 分隔线 (Divider)

```
Width: 1pt (hover 时变为 2pt)
Background: border color
Cursor: col-resize
Hover background: accent color
Hit area: ±3pt（通过 ::after 伪元素扩大）
```

### 6.6 内容面板 (Content Panel / Terminal Area)

```
Flex: 1（占据侧栏右侧所有剩余空间）
Background: color-mix(bg 50%, surface)
Overflow: hidden
背景纹理：repeating horizontal lines (23.5pt 间距，0.3 透明度) — 模拟终端行号
```

**终端占位区：**
- 居中显示：终端图标 48×48 (muted, 0.5 opacity) + 标签名称 (mono, muted) + 提示文字 (caption, muted, 0.6 opacity)

**侧边栏通知提示 (Panel Toast)：**
- 位置：内容面板左上角 (top: 16pt, left: 16pt)
- 胶囊外形：padding 6pt 12pt, border-radius Capsule
- 文字："标签页四有新通知 ←"
- 非交互元素 (pointer-events: none)，opacity 0.7

### 6.7 空状态 (Empty State)

```
Layout: 居中 flex column, gap 20pt, padding 48pt, text-align center
图标: 64×64 (muted, 0.35 opacity)
标题: 20pt, display, Semibold, -0.02em
描述: 13pt, muted, max-width 28ch
按钮: 36pt 高, accent 实心胶囊, 图标 + 文字
```

---

## 7. 任务完成气泡 (Task Completion Bubble) — 新增组件

### 7.1 触发条件
- 用户在标签页一工作，标签页四的后台任务完成
- 标签页四状态点变绿色脉冲 + 徽标变「任务完成」
- 气泡从标签行下方内联展开

### 7.2 气泡形态

```
形状：圆角 0 0 14px 14px（顶部与标签行无缝衔接，标签行底部圆角移除）
向上尖角：10×10pt 方块旋转 45°，定位 left: ~23pt（对齐状态点中心）
背景：绿色半透明 (green-soft2 80% + surface)
描边：0.5pt 半透明绿色
阴影：shadow-sm
左右外边距：12pt（与标签行 padding 一致）
```

### 7.3 气泡内部布局

```
[header: check icon 18×18 + title + timestamp]
  ↓ gap 12pt
[body: 结果列表（绿点 + 文字）× 3]
  ↓ gap 12pt
[actions: 查看详情（绿色实心胶囊） + 知道了（描边胶囊）]
```

**对齐基准（从侧栏左边缘算起）：**
| 层级 | 水平位置 | 计算 |
|------|---------|------|
| 侧栏 padding | 8pt | - |
| 标签行内容起点 | 20pt | 8 + 12 |
| 状态点中心 | ~23.5pt | 20 + 7/2 |
| 气泡左边缘 | 12pt | = 标签行 padding |
| 气泡标题起点 | 54pt | 12 + 16 + 26 |
| 气泡正文起点 | 54pt | 12 + 16 + 26（与标题对齐） |

### 7.4 气泡内按钮

**主操作「查看详情」：**
```
Height: 28pt
Padding: 0 14pt
Border-radius: Capsule
Background: green 实心
Color: white
Shadow: 0 1px 2px rgba(0,0,0,0.1)
Hover: brightness(1.08) + shadow 扩大 + translateY(-0.5px)
Active: scale(0.97)
```

**次要操作「知道了」：**
```
Height: 28pt
Padding: 0 12pt
Border-radius: Capsule
Border: 0.5pt hairline
Background: transparent
Color: muted
Hover: color→fg, border→muted, background→fg-soft
Active: scale(0.97)
```

### 7.5 气泡动画

**入场：** `max-height: 0 → 300px` + opacity 0→1，400ms spring curve
**退出：** 逆向收起 + 淡出，400ms

### 7.6 交互行为

1. **气泡出现：** 任务完成时自动展开，状态点脉冲动画持续
2. **查看详情：** 切换选中到完成标签 → 右侧面板显示该终端 → 气泡收起
3. **知道了：** 仅关闭气泡，用户留在当前标签，脉冲停止
4. **不遮挡：** 气泡在侧栏内展开，不遮挡右侧终端画面

---

## 8. 动画与过渡

| 属性 | 时长 | 缓动 |
|------|------|------|
| 颜色过渡 (background/color/border) | 150ms | ease-out |
| 主题切换 | 250ms | ease-out |
| 气泡展开/收起 | 400ms | spring |
| 状态点脉冲 | 2000ms | ease-out (infinite) |
| 按钮 hover 浮起 | 150ms | ease-out |
| 按钮 active 按压 | - | scale(0.97) |

**CSS 缓动函数：**
```css
--ease-out:   cubic-bezier(0.16, 1, 0.3, 1);
--ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1);
```

---

## 9. 布局结构

```
┌──────────────────────────────────────────────────────────┐
│  Toolbar (44pt)                                           │
│  [终端图标] NARC Workspace · N 个终端    [主题] [新建终端]  │
├────────────────────┬──┬──────────────────────────────────┤
│                    │  │                                  │
│  Sidebar (300pt)   │分│  Content Panel (flex: 1)         │
│                    │隔│                                  │
│  ┌─ 运行中 ────────│线│  终端实时画面占位区                │
│  │ tab-row (选中)   │  │                                  │
│  │ tab-row (默认)   │  │                                  │
│  │                 │  │                                  │
│  ├─ 需关注 ────────│  │                                  │
│  │ tab-row (红色)   │  │                                  │
│  │                 │  │                                  │
│  ├─ 已完成 ────────│  │                                  │
│  │ tab-row (绿色)   │  │                                  │
│  │ └ 气泡卡片       │  │                                  │
│  │                 │  │                                  │
│  ├─ 已结束 ────────│  │                                  │
│  │ tab-row (灰色)   │  │                                  │
│  └─────────────────│  │                                  │
│                    │  │                                  │
└────────────────────┴──┴──────────────────────────────────┘
```

---

## 10. 关键设计决策汇总

1. **分隔线替代方案：** 标签行间不用可见分隔线，用 2pt 间距 + 独立圆角背景。hover/选中时背景浮现 = 自然分界。
2. **需关注红态：** 左侧 3pt 红条 + 10% 淡红底色，非全饱和红色块。醒目但不刺眼。
3. **连续曲率：** CSS `border-radius` 无法做 squircle，用比传统大的值逼近，SwiftUI 层用 `.continuous`。
4. **工具栏材质：** 半透明 + `blur(20px)` 模拟 macOS 毛玻璃。
5. **气泡定位：** 选择侧栏标签行下方内联展开（非浮出 Popover）。理由：关联明确、不遮挡终端画面、可随侧栏滚动。
6. **按钮高度统一：** 所有胶囊按钮（toolbar 切换、新建终端、气泡主/次操作）统一 28pt。
7. **操作按钮可点击区：** 从 22×22 扩大到 24×24，防止误触。
8. **侧栏区块分组：** uppercase 标签按状态分组（运行中 / 需关注 / 已完成 / 已结束），label 间距统一 8pt margin-top。

---

## 11. 深浅模式适配要点

- 浅色模式阴影：低透明度（4-6%），靠叠加层数表达层次
- 深色模式阴影：高透明度（25-55%），单层也可感知
- 浅色模式柔和底色：10-12% 透明度
- 深色模式柔和底色：12-15% 透明度
- 所有过渡带 250ms ease-out，切换时平滑渐变
- 毛玻璃工具栏：浅色 `color-mix(bg 85%, transparent)`，深色同样公式成立
- 内阴影方向颠倒：浅色用黑半透明，深色用白半透明

---

## 12. 参考文件

- 高保真原型：`narc-dashboard-soft-v5-5.html`（本文档的视觉来源）
- 先前迭代：`narc-dashboard-soft-v5-4.html`（气泡初版）、`narc-dashboard-soft-v5-3.html`（布局修正）、`narc-dashboard-soft-v5-2.html`（首版左右分栏）
- 原始改版：`narc-dashboard-soft.html` 至 `narc-dashboard-soft-redesign-4.html`
