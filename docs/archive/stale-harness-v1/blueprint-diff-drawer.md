# Blueprint: 文件变更 Diff 抽屉
- 对应 PRD: docs/PRD-diff-drawer.md
- 蓝图状态: Confirmed（2026-06-22 用户确认）
- 目标执行方: 🔵 弱模型
- 技术栈: Swift 5.9 / SwiftUI + AppKit

> 全部改动集中在 `NARC/Sources/Views/DashboardView.swift`（外加 `FileChange` 无需改）。无新增依赖、无新增权限、无 Model/Service 改动。

## 🗂️ 文件级实现规划

### `NARC/Sources/Views/DashboardView.swift`（修改）

**改动 1 — 状态**（当前 19-21 行附近）：把单一 `diffContent` 扩成结构化：
```swift
@State private var diffFile: FileChange?
@State private var diffRows: [DiffRow] = []     // 解析后的结构化行
@State private var diffAdded: Int = 0
@State private var diffRemoved: Int = 0
@State private var diffEmptyMessage: String? = nil   // 无差异/错误时的友好文案
@State private var diffLoading: Bool = false
```

**改动 2 — `loadDiff(for:)`**（当前 58-89 行）整体替换：
```swift
private func loadDiff(for file: FileChange) {
    diffLoading = true
    diffRows = []; diffAdded = 0; diffRemoved = 0; diffEmptyMessage = nil
    let cwd = selectedSession?.cwd ?? (file.path as NSString).deletingLastPathComponent
    let path = file.path
    DispatchQueue.global(qos: .userInitiated).async {
        func git(_ args: [String]) -> String {
            let t = Process()
            t.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            t.arguments = ["-C", cwd] + args
            let pipe = Pipe(); t.standardOutput = pipe; t.standardError = FileHandle.nullDevice
            do { try t.run(); t.waitUntilExit() } catch { return "" }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }
        // 1) staged + unstaged 相对 HEAD
        var raw = git(["diff", "HEAD", "--", path])
        // 2) 新文件(untracked) → 全量新增
        if raw.isEmpty {
            let status = git(["status", "--porcelain", "--", path])
            if status.hasPrefix("??") || status.hasPrefix("A") {
                raw = git(["diff", "--no-index", "--", "/dev/null", path])
            }
        }
        let parsed = DiffParser.parse(raw)
        DispatchQueue.main.async {
            diffRows = parsed.rows
            diffAdded = parsed.added
            diffRemoved = parsed.removed
            diffEmptyMessage = parsed.rows.isEmpty ? "该文件相对工作区暂无差异（可能已提交或被还原）" : nil
            diffLoading = false
        }
    }
}
```

**改动 3 — `rightColumn`**（当前 169-197 行）：把 diff 从 VStack 底部移到**右侧 overlay 抽屉**：
```swift
} else {
    VStack(spacing: 0) {
        terminalPane.frame(maxWidth: .infinity, maxHeight: .infinity)
        Divider()
        FileChangePanel(
            files: selectedSession?.touchedFiles.reversed() ?? [],
            selectedPath: diffFile?.path,
            onFileTap: { diffFile = $0 }
        )
        .frame(height: 100)
    }
    .background(Color.narcBackground)
    .overlay(alignment: .trailing) {
        if diffFile != nil {
            diffDrawer
                .frame(width: 460)
                .background(Color.narcBackground)
                .overlay(Rectangle().frame(width: 0.5).foregroundColor(.narcBorder), alignment: .leading)
                .shadow(color: .black.opacity(0.12), radius: 16, x: -4)
                .transition(.move(edge: .trailing))
        }
    }
    .animation(.narcSoft, value: diffFile?.path)
}
```
> 删除原 VStack 里 `if diffFile != nil { Divider(); diffDrawer.frame(maxHeight:200) }` 那段（174-184 行）。

**改动 4 — `diffDrawer`**（当前 223-270 行）整体替换为右侧抽屉版（头 + 折叠/着色正文）：
```swift
private var diffDrawer: some View {
    VStack(spacing: 0) {
        // 头：文件名 + 面包屑 + +X −Y + 打开 + 关闭
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "doc.text.magnifyingglass").foregroundColor(.narcAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text((diffFile?.path as NSString?)?.lastPathComponent ?? "")
                    .font(.narcCaption).fontWeight(.medium).foregroundColor(.narcText).lineLimit(1)
                Text(breadcrumb(diffFile?.path))
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.narcTextFaint)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            if diffAdded > 0 { summaryPill("+\(diffAdded)", .narcSuccess) }
            if diffRemoved > 0 { summaryPill("−\(diffRemoved)", .narcDanger) }
            Button { if let p = diffFile?.path { NSWorkspace.shared.open(URL(fileURLWithPath: p)) } }
                label: { Image(systemName: "arrow.up.forward.app") }.buttonStyle(.plain).help("在编辑器打开")
            Button { diffFile = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭")
        }
        .padding(.horizontal, NarcSpacing.md).padding(.vertical, NarcSpacing.sm)
        .background(Color.narcSurfaceMuted.opacity(0.6))
        Divider()
        // 正文
        if diffLoading { /* ProgressView 居中（沿用现有） */ }
        else if let msg = diffEmptyMessage { /* 居中友好空态文案 + icon */ }
        else { DiffRowsView(rows: diffRows) }
    }
}
```
辅助：`breadcrumb(_:)`（路径转 `~/…` 去掉文件名）、`summaryPill(_:_:)`（等宽小胶囊）。

**改动 5 — 新增类型/视图/解析器**（放文件末尾，替换 `DiffContentView`/`DiffLineView`）：
```swift
struct DiffRow: Identifiable {
    enum Kind { case context, add, del, gap }
    let id = UUID()
    let kind: Kind
    let oldNum: Int?
    let newNum: Int?
    let text: String        // 去掉 +/- 符号的代码；gap 时为 "N 行未改动"
}

enum DiffParser {
    static func parse(_ raw: String) -> (rows: [DiffRow], added: Int, removed: Int) {
        var rows: [DiffRow] = []; var added = 0; var removed = 0
        var oldLine = 0; var newLine = 0; var lastNew = 0; var seenHunk = false
        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("--- ")
               || line.hasPrefix("+++ ") || line.hasPrefix("new file") || line.hasPrefix("deleted file")
               || line.hasPrefix("similarity ") || line.hasPrefix("rename ") || line.hasPrefix("\\ ") { continue }
            if line.hasPrefix("@@") {
                let (a, c) = hunkStarts(line)
                if seenHunk { let gap = c - lastNew - 1
                    if gap > 0 { rows.append(DiffRow(kind: .gap, oldNum: nil, newNum: nil, text: "\(gap) 行未改动")) } }
                oldLine = a; newLine = c; seenHunk = true; continue
            }
            guard seenHunk else { continue }
            if line.hasPrefix("+") {
                rows.append(DiffRow(kind: .add, oldNum: nil, newNum: newLine, text: String(line.dropFirst())))
                newLine += 1; lastNew = newLine - 1; added += 1
            } else if line.hasPrefix("-") {
                rows.append(DiffRow(kind: .del, oldNum: oldLine, newNum: nil, text: String(line.dropFirst())))
                oldLine += 1; removed += 1
            } else {
                let t = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                rows.append(DiffRow(kind: .context, oldNum: oldLine, newNum: newLine, text: t))
                oldLine += 1; newLine += 1; lastNew = newLine - 1
            }
        }
        return (rows, added, removed)
    }
    // 从 "@@ -a,b +c,d @@" 取 a(旧起) 与 c(新起)
    private static func hunkStarts(_ s: String) -> (Int, Int) {
        var o = 0, n = 0
        for p in s.split(separator: " ") {
            if p.hasPrefix("-") { o = Int(p.dropFirst().split(separator: ",").first ?? "") ?? 0 }
            else if p.hasPrefix("+") { n = Int(p.dropFirst().split(separator: ",").first ?? "") ?? 0 }
        }
        return (o, n)
    }
}
```
`DiffRowsView`：`ScrollView([.vertical,.horizontal])` + `LazyVStack` 渲染每行：
- `.gap`：居中细条 `ellipsis` + 文案，`narcSurfaceMuted.opacity(0.5)` 底，`narcTextFaint`。
- `.context/.add/.del`：`HStack(spacing:0)` = 旧行号槽(宽38,右对齐,faint) + 新行号槽 + 代码（等宽12pt）。add 绿底(`narcSuccess.opacity(0.10)`)+绿字+`+`；del 红底+红字+`−`；context 透明+主色。

**改动 6 — `FileChangeRow` / `FileChangePanel`**（当前 842-969 行）：
- emoji → SF Symbols：`toolIcon` 返回 `Image(systemName:)`：Edit=`pencil`、Write=`plus.square`、Read=`eye`、其它=`arrow.right`，统一 `narcAccent`/`narcTextMuted` 着色。
- `FileChangePanel` 加参数 `var selectedPath: String? = nil`；`FileChangeRow` 加 `isSelected: Bool`，选中时整行 `.softRowBackground(isSelected:true,...)` 或 `narcAccent.opacity(0.12)` 连续曲率底。

## 🚫 禁止项清单
- ❌ 不做语法高亮 / word-diff（本期排除）。
- ❌ 不碰 `dedent` / `SmartCopyBubble` / 智能复制逻辑。
- ❌ 不改 `FloatingWidgetContainer.computedState` 与降噪逻辑。
- ❌ 不引第三方库；diff 一律走 `Process` + 系统 git。
- ❌ 不按 git 退出码判错（`--no-index` 正常返回 1）。
- ❌ 行号槽宽度别写死到放不下 4 位数——用 ≥38pt。

## ✅ 实现完成的判定
- [ ] 点列表文件 → 右侧抽屉滑入覆盖终端，✕ 可关，切换文件平滑。
- [ ] diff 无 `diff --git`/`index`/`+++`/`---` 噪声；有双列行号；+/- 软色；大段未改动显示「N 行未改动」。
- [ ] 抽屉头有文件名 + 面包屑 + `+X −Y` + 打开 + 关闭。
- [ ] 新文件(untracked) 显示全量新增；staged 文件有 diff；真无差异显示友好文案。
- [ ] 列表无 emoji（SF Symbols），选中行高亮。
- [ ] `swift build` 通过；终端/Tab/智能复制无回归。

## 🧠 来自 Brain / config 约束
- 视觉遵循 `DesignTokens` v5.5（连续曲率、`narcSuccess/narcDanger`、间距阶）。
- 沿用 config constraints：UI 定位实测、SwiftTerm internal API 不碰（本特性不涉及）。
