# NARC Design ↔ Code 协作协议

## 目的

让 Design AI（Open Design）和 Code AI（Claude Code）通过 **共享 Git 仓库** 协作，消除手动搬运中间产物的断点。

---

## 文件所有权划分

| 目录/文件 | Owner | 说明 |
|-----------|-------|------|
| `Sources/Design/` | **Design** | 设计 Token、共享样式、动画定义 |
| `Sources/Views/` | **Design** (结构) + **Code** (逻辑) | Design 写 UI 结构和视觉；Code 接线业务逻辑 |
| `Sources/Services/` | **Code** | 业务逻辑、系统 API、网络层 |
| `Sources/App/` | **Code** | AppDelegate、窗口管理、系统集成 |
| `Sources/Utils/` | **Code** | 底层工具（AX API、坐标转换） |
| `Sources/Models/` | **Code** | 数据模型 |
| `design-handoff/` | **Design** | 交接产物（见下） |

---

## Design → Code 交接格式

Design AI 完成一批设计后，将产物写到 `design-handoff/` 目录，然后提交到 `design/*` 分支：

```
design-handoff/
├── CURRENT.md              ← 本次交接的变更摘要（人读）
├── tokens-diff.swift       ← DesignTokens.swift 的增量（可直接 copy-paste 或 merge）
├── views/                  ← 新建/重写的 View 文件（完整 .swift）
│   ├── SomeNewView.swift
│   └── UpdatedPanelView.swift
└── assets/                 ← 如有新增 SF Symbol 自定义 / 图片资源
```

### CURRENT.md 格式

```markdown
# Design Handoff — [日期]

## 变更列表
- [ ] 新增 `XxxView.swift` — [简述功能]
- [ ] 修改 `DesignTokens.swift` — 新增 3 个 color token
- [ ] 重写 `PanelView.swift` — tab bar 改为侧边栏

## 依赖说明
- 需要 Code 侧新增 `XxxService` 提供数据
- 需要 Code 侧在 AppDelegate 注册新窗口

## 编译须知
- 新增了 SPM 依赖：无 / [包名]
- 新增了系统权限：无 / [权限名]
```

---

## Code 侧接收流程

Claude Code 收到 Design 分支后：

1. `git merge design/xxx` 或 `git cherry-pick`
2. 编译验证 `swift build`
3. 接线业务逻辑（传入 Service、绑定 Model、注册窗口）
4. 功能测试
5. 提交到 `main`

---

## 共享上下文（Design AI 必须读的文件）

Design AI 开始工作前，应先读以下文件获取当前上下文：

```
必读（每次）：
- Sources/Design/DesignTokens.swift     ← 当前 Token 系统
- Sources/Models/Models.swift           ← 数据模型（View 要绑定的数据）
- README.md                             ← 功能全景

按需读：
- Sources/Views/[目标文件].swift        ← 要修改的现有 View
- Sources/Services/[相关 Service].swift ← 理解数据从哪来
```

---

## Git 分支约定

| 分支 | 用途 |
|------|------|
| `main` | 稳定版本（Code 负责） |
| `design/[feature-name]` | Design AI 的工作分支 |
| `feat/[feature-name]` | Code AI 的功能分支 |

---

## 给 Design AI 的 System Prompt 建议

把以下内容加到 Design AI 的上下文中：

```
你正在为 NARC for Mac（SwiftUI macOS app）做 UI 设计和前端实现。

项目路径：~/narc_for_mac
设计 Token：Sources/Design/DesignTokens.swift（所有颜色/字体/间距/动画从这里引用）
完整设计规格：见 Open Design 项目中的 DESIGN.md（包含颜色系统、圆角阶梯、阴影层次、间距体系、组件规格、气泡通知等完整规范）
  → 路径: ~/Library/Application Support/Open Design/namespaces/release-stable/data/projects/4756a449-e37d-418b-8c2a-752d680cb835/DESIGN.md
  → 高保真 HTML 原型: narc-dashboard-soft-v5-5.html (同目录)

你的输出规则：
1. 直接写完整的 .swift 文件（不是伪代码，不是 MD 描述）
2. 所有颜色用 Color.narcXxx，字体用 Font.narcXxx，间距用 NarcSpacing.xxx
3. 不要碰 Sources/Services/ 和 Sources/App/ 下的文件
4. 如果需要 Service 提供数据，在 View 的 init 参数中声明，注释 `// TODO: Code 侧接线`
5. 输出到 design-handoff/views/ 目录
6. 写 design-handoff/CURRENT.md 说明变更

项目 Design Token 快速参考 (v5.5 软化改版):
- 颜色：narcBackground, narcSurface, narcSurfaceMuted, narcText, narcTextMuted, narcTextFaint, narcBorder, narcAccent, narcSuccess, narcWarn, narcDanger, narcInfo
- 字体：narcDisplayXL(28), narcDisplay(22), narcTitle(17), narcSubtitle(14), narcBody(13), narcCaption(11), narcMono(12), narcMonoSmall(11), narcMonoTiny(9)
- 间距：NarcSpacing.xxs(2) xs(4) sm(8) md(12) lg(16) xl(20) xxl(24) xxxl(32) xxxxl(40) xxxxxl(48)
- 圆角 (v5.5 更新)：NarcRadius.xs(6) sm(10) md(14) lg(20) xl(24) pill(999) — 全部使用 .continuous 样式
- 动画：Animation.narcSnap, .narcSoft, .narcEase, .narcBreath
- 毛玻璃：VisualEffectBackground(material: .hudWindow/.menu/.popover)
- 呼吸光：.breathingHalo(active: Bool)
- 柔和行背景：.softRowBackground(isSelected:needsAttention:isHovering:)
- 分层阴影：.softShadow("xs"|"sm"|"md"|"lg")
```

---

## 给 Claude Code 的补充规则

在 CLAUDE.md 或会话中添加：

```
## Design 协作

- design-handoff/ 目录下的 .swift 文件是 Design AI 的产出，可以直接使用
- 接收时：先编译验证 → 再接线 Service/Model → 最后功能测试
- 如果 Design 的代码有编译错误，修复时保持视觉意图不变
- Token 冲突时以 DesignTokens.swift 为准（Design 拥有 Token 定义权）
```
