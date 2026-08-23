# PRD: 文件变更 Diff 抽屉

## 📌 需求摘要
- 一句话：把 Dashboard 的「文件变更 diff」从底部原始文本小条，改造成**右侧滑出抽屉 + 折叠式结构化 diff**，并修掉"新文件/已暂存文件显示无内容"的 bug。
- 类型：重构 + Bug 修复（UI 可读性）
- 优先级：P1

## 🎯 目标与边界

### 核心目标
点击「最近文件变更」里的文件 → 在右侧滑出一个干净、易读的 diff 抽屉，覆盖终端区；看完关闭回到终端。可读性对齐 Claude 的 diff 体验，视觉对齐 v5.5 软化风格。

### 核心场景
1. Claude 在某 Tab 里 Edit 了 `FloatingWidgetView.swift` → 列表出现该文件 → 我点它 → 右侧抽屉滑出，顶部显示 `+3 −2`，正文只看到改动行 + 少量上下文，中间没改的折叠成「26 行未改动」→ 看完点 ✕ 关闭。
2. Claude 用 Write 新建了 `SmartCopyBubble.swift`（untracked）→ 点它 → 抽屉显示**全量新增**（绿色），而不是现在的"无变更内容"。

### 明确排除（本期不做）
- ❌ **语法高亮**（按语言 token 着色）——本期只做 +/- 行着色 + 行号 + 折叠（用户确认"折叠档"）。
- ❌ 行内字符级 diff（word-diff）。
- ❌ diff 内编辑 / 应用 / 还原（只读展示）。
- ❌ 列表里每个文件的 +/− 行数徽标（需逐文件 git 调用，留作后续；汇总只在抽屉头显示）。

### 验收标准
1. 点列表文件 → **右侧滑出抽屉**覆盖终端区（非底部小条），有进出动画，可 ✕ 关闭。
2. diff 正文：**去噪**（不显示 `diff --git`/`index`/`---`/`+++`）；**双列行号**（旧/新）；**+/- 软色着色**（绿/红低透底 + 符号）；大段未改动**折叠为「N 行未改动」**分隔条。
3. 抽屉头：文件名 + 路径面包屑 + **`+X −Y` 汇总** + "在编辑器打开" + 关闭。
4. **修复 git diff bug**：已暂存(staged)文件用 `git diff HEAD` 兜住；新文件(untracked)用 `git diff --no-index` 显示全量新增；真无差异才显示友好空态文案。
5. 列表去 emoji（📝✏️👁 → SF Symbols 按 Edit/Write/Read 区分），**选中文件行高亮**（连续曲率柔和底）。
6. `swift build` 通过，现有终端/Tab/智能复制无回归。

## 👤 用户旅程
点列表行 → `diffFile` 置值 → 抽屉从右侧 `.move(edge:.trailing)` 滑入 → 异步跑 git diff（HEAD / no-index）→ 解析为结构化行 → 渲染（行号槽 + 着色 + 折叠）→ ✕ 或点另一行切换 → `diffFile=nil` 滑出。

## ⚙️ 技术约束
- 复用现有 `git diff` 子进程方式（`Process`）；只改参数与解析。
- 视觉走 `DesignTokens`（v5.5：连续曲率、`narcSuccess/narcDanger` 低透、间距阶）；diff 正文用等宽字体。
- 不引第三方库。

## ⚠️ 风险与依赖
- `git diff --no-index` 对差异返回 exit code 1（正常）——读 stdout，不按退出码判错（现有代码已如此）。
- 抽屉覆盖右栏会盖住部分「最近文件变更」列表——可接受（抽屉宽 ~460，左侧仍可点）。
- 解析器需正确处理 `@@` 跨 hunk 的行号跳变以算「N 行未改动」。

## 📋 任务粗拆
| # | 任务 | 复杂度 | 文件 |
|---|------|--------|------|
| 1 | unified diff 解析器（行号/类型/折叠） | 中 | DashboardView.swift |
| 2 | `loadDiff` 修 git 调用（HEAD + no-index 兜底） | 中 | DashboardView.swift |
| 3 | diff 改右侧抽屉 overlay + 进出动画 | 中 | DashboardView.swift |
| 4 | 抽屉头（面包屑 + 汇总 + 打开/关闭）+ 折叠/着色行视图 | 中 | DashboardView.swift |
| 5 | 列表去 emoji + 选中高亮 | 低 | DashboardView.swift |
| 6 | 回归手测 | 低 | — |

## 📝 攻防记录
- 抽屉 vs 切换 vs 内联 → 用户选**抽屉**。
- 语法高亮要不要 → 用户选**折叠档**（不做语法高亮）。
- 发现真 bug：现用 `git diff` 对 untracked/staged 显示空 → 纳入本期一并修。
