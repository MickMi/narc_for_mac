import SwiftUI

/// Dashboard with embedded multi-terminal workspace.
/// - Top toolbar: new-terminal menu (Shell / Claude).
/// - Left column: list of in-NARC terminal sessions (each is its own PTY+child).
/// - Right column: live, interactive terminal of the selected session.
///
/// Sessions are kept alive by rendering all panes in a ZStack; only the selected
/// one is visible/interactive. ClaudeService is kept around for future status
/// badge enrichment but not used by the MVP.
///
/// `terminals` is owned by AppDelegate (not @StateObject here) so closing the
/// Dashboard window doesn't tear it down — child PTYs keep running and the
/// next time the window is summoned we see the same tabs / output / state.
struct DashboardView: View {
    @ObservedObject var claudeService: ClaudeSessionService
    @ObservedObject var terminals: TerminalSessionManager

    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 13

    @State private var diffFile: FileChange?
    @State private var diffRows: [DiffRow] = []
    @State private var diffAdded: Int = 0
    @State private var diffRemoved: Int = 0
    @State private var diffEmptyMessage: String? = nil
    @State private var diffLoading: Bool = false
    @State private var fileStats: [String: (added: Int, removed: Int)] = [:]
    @State private var showFileChanges = false
    @State private var showDiffDrawer = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                leftColumn
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
                rightColumn
                    .frame(minWidth: 420, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color.narcBackground)
        .overlay(alignment: .topLeading) {
            // ⌘1–⌘9 tab switching — hidden buttons in the view hierarchy
            // so SwiftUI routes keyboard shortcuts to the correct action.
            ForEach(Array(terminals.sessions.prefix(9).enumerated()), id: \.element.id) { idx, session in
                Button(action: { terminals.selectedId = session.id }) {}
                    .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0)
            }
        }
        .onChange(of: terminals.sessions.map(\.id)) { _, _ in
            if terminals.selectedId == nil
                || !terminals.sessions.contains(where: { $0.id == terminals.selectedId }) {
                terminals.selectedId = terminals.sessions.last?.id
            }
        }
        .onAppear {
            if terminals.selectedId == nil {
                terminals.selectedId = terminals.sessions.last?.id
            }
        }
        .onChange(of: diffFile?.path) { _, newPath in
            if let file = diffFile {
                loadDiff(for: file)
                if newPath != nil { showDiffDrawer = true }
            } else {
                diffRows = []
                diffAdded = 0
                diffRemoved = 0
                diffEmptyMessage = nil
                showDiffDrawer = false
            }
        }
        .onChange(of: terminals.selectedId) { _, _ in
            showFileChanges = false
            showDiffDrawer = false
            diffFile = nil
            refreshFileStats()
        }
        .onChange(of: selectedSession?.touchedFiles.count) { _, _ in
            refreshFileStats()
        }
    }

    /// Run `git diff` for the given file.
    ///
    /// Strategy (in order):
    /// 1. Locate the git repo root from the file's parent directory — this is
    ///    more reliable than `selectedSession?.cwd` which may point to a
    ///    non-git directory (e.g. home dir after `cd ~`).
    /// 2. `git diff HEAD -- <path>` captures staged + unstaged changes.
    /// 3. If that produces nothing, check `git status --porcelain` for
    ///    untracked / staged-new / working-tree-modified states, and fall
    ///    back to `git diff --no-index -- /dev/null <path>`.
    /// 4. If the repo has no commits yet (orphan branch), `HEAD` won't
    ///    resolve — fall back to comparing against /dev/null directly.
    private func loadDiff(for file: FileChange) {
        diffLoading = true
        diffRows = []; diffAdded = 0; diffRemoved = 0; diffEmptyMessage = nil
        let path = file.path
        // Resolve git repo root from the file's location, not from terminal cwd.
        let fileDir = (path as NSString).deletingLastPathComponent
        let repoRoot = Self.gitRepoRoot(near: fileDir)
        DispatchQueue.global(qos: .userInitiated).async {
            func git(_ args: [String]) -> String {
                let t = Process()
                t.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                if let root = repoRoot {
                    t.arguments = ["-C", root] + args
                } else {
                    t.arguments = args
                    t.currentDirectoryURL = URL(fileURLWithPath: fileDir)
                }
                let pipe = Pipe(); t.standardOutput = pipe; t.standardError = FileHandle.nullDevice
                do { try t.run(); t.waitUntilExit() } catch { return "" }
                return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            }

            // 1) staged + unstaged relative to HEAD (tracks both tracked & staged-new files)
            var raw = git(["diff", "HEAD", "--", path])
            let headCheck = git(["rev-parse", "--verify", "HEAD"])
            let noHead = headCheck.isEmpty

            // 2) If HEAD diff is empty, try other approaches
            if raw.isEmpty {
                let status = git(["status", "--porcelain", "--", path])
                // Untracked / staged-new / working-tree-modified / no-HEAD → full file
                if noHead
                    || status.hasPrefix("??")
                    || status.hasPrefix("A")
                    || status.hasPrefix(" M")
                    || status.hasPrefix("M ") {
                    raw = git(["diff", "--no-index", "--", "/dev/null", path])
                }
            }

            let parsed = DiffParser.parse(raw)
            DispatchQueue.main.async {
                diffRows = parsed.rows
                diffAdded = parsed.added
                diffRemoved = parsed.removed
                if parsed.rows.isEmpty {
                    diffEmptyMessage = raw.isEmpty
                        ? "该文件不在 Git 仓库中，或 git 命令执行失败"
                        : "该文件相对工作区暂无差异（可能已提交或被还原）"
                } else {
                    diffEmptyMessage = nil
                }
                diffLoading = false
            }
        }
    }

    /// Find the git repository root nearest to the given directory.
    private static func gitRepoRoot(near dir: String) -> String? {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        t.arguments = ["-C", dir, "rev-parse", "--show-toplevel"]
        let pipe = Pipe(); t.standardOutput = pipe; t.standardError = FileHandle.nullDevice
        do { try t.run(); t.waitUntilExit() } catch { return nil }
        guard t.terminationStatus == 0,
              let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !out.isEmpty else { return nil }
        return out
    }

    /// Refresh per-file +/- line counts via a single `git diff --numstat HEAD` call.
    /// Uses the same git-repo-root discovery strategy as `loadDiff`.
    private func refreshFileStats() {
        // Find a representative directory to locate the git repo: the first
        // touched file's parent, falling back to the selected session's cwd.
        let probeDir: String? = selectedSession?.touchedFiles.first.map {
            ($0.path as NSString).deletingLastPathComponent
        } ?? selectedSession?.cwd
        guard let probeDir = probeDir,
              let repoRoot = Self.gitRepoRoot(near: probeDir) else {
            fileStats = [:]
            return
        }
        DispatchQueue.global(qos: .utility).async {
            func git(_ args: [String]) -> String {
                let t = Process()
                t.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                t.arguments = ["-C", repoRoot] + args
                let pipe = Pipe(); t.standardOutput = pipe; t.standardError = FileHandle.nullDevice
                do { try t.run(); t.waitUntilExit() } catch { return "" }
                return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            }
            var stats: [String: (added: Int, removed: Int)] = [:]
            let raw = git(["diff", "--numstat", "HEAD"])
            for line in raw.components(separatedBy: "\n") {
                let parts = line.split(separator: "\t")
                guard parts.count == 3,
                      let add = Int(parts[0]), let del = Int(parts[1]) else { continue }
                let path = String(parts[2])
                stats[path] = (added: add, removed: del)
            }
            // Also handle untracked files: count all lines as "added"
            let statusRaw = git(["status", "--porcelain"])
            for line in statusRaw.components(separatedBy: "\n") {
                guard line.hasPrefix("??") || line.hasPrefix("A") else { continue }
                let relPath = String(line.dropFirst(3))
                if stats[relPath] == nil {
                    let absPath = repoRoot + "/" + relPath
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: absPath)),
                       let content = String(data: data, encoding: .utf8) {
                        let lineCount = content.components(separatedBy: "\n").count - 1
                        stats[relPath] = (added: max(lineCount, 0), removed: 0)
                    }
                }
            }
            DispatchQueue.main.async { fileStats = stats }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(Color.narcAccent)
            Text("NARC Workspace")
                .font(.narcSubtitle)
                .foregroundStyle(Color.narcText)
            Text("·")
                .foregroundStyle(Color.narcTextMuted)
            Text("\(terminals.sessions.count) 个终端")
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)

            Spacer()

            // ── 变更文件 ──
            let fileCount = selectedSession?.touchedFiles.count ?? 0
            if fileCount > 0 {
                Button(action: { showFileChanges.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                        Text("变更文件")
                            .font(.narcCaption)
                        Text("\(fileCount)")
                            .font(.narcMonoTiny)
                            .foregroundColor(.narcAccent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.narcAccent.opacity(0.12)))
                    }
                    .foregroundColor(.narcTextMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().strokeBorder(Color.narcBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showFileChanges, arrowEdge: .bottom) {
                    FileChangePopover(
                        files: selectedSession?.touchedFiles.reversed() ?? [],
                        selectedPath: diffFile?.path,
                        fileStats: fileStats,
                        onFileTap: { file in
                            showFileChanges = false
                            diffFile = file
                            showDiffDrawer = true
                        }
                    )
                }
            }

            // ── 差异对比 ──
            if diffFile != nil {
                Button(action: { showDiffDrawer.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                        Text("差异对比")
                            .font(.narcCaption)
                    }
                    .foregroundColor(showDiffDrawer ? .white : .narcTextMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(showDiffDrawer ? Color.narcAccent : .clear)
                    )
                    .overlay(
                        Capsule().strokeBorder(showDiffDrawer ? Color.clear : Color.narcBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }

            Button(action: spawnShell) {
                HStack(spacing: NarcSpacing.xs) {
                    Image(systemName: "plus")
                    Text("新建终端")
                        .font(.narcCaption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, NarcSpacing.md)
                .padding(.vertical, NarcSpacing.xs + 2)
                .background(Capsule().fill(Color.narcAccent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .background(.regularMaterial)
    }

    // MARK: - Left Column (Tab list)

    /// Estimated row height used for drag-reorder target-index calculation.
    /// Chrome-style drag: the whole row is draggable, the original becomes
    /// transparent, a same-size floating preview follows the mouse, and other
    /// rows animate aside to show the insertion point.
    private static let tabRowHeight: CGFloat = 56
    /// Measured width of the VStack content area, so the floating drag preview
    /// matches the exact width of the tab rows (not the full ZStack).
    @State private var listContentWidth: CGFloat = 200

    private var tabDragPreviewWidth: CGFloat {
        min(max(120, listContentWidth - NarcSpacing.lg), 260)
    }

    /// Helper that creates a TerminalTabRow with the shared wiring so the
    /// left column and the floating drag preview always look identical.
    private func makeTabRow(session: OwnedSession, idx _: Int) -> some View {
        let pendingApproval = claudeService.pendingApprovals.first {
            $0.narcSessionId == session.id.uuidString
        }
        return TerminalTabRow(
            session: session,
            isSelected: session.id == terminals.selectedId,
            approval: pendingApproval,
            onTap: { terminals.selectedId = session.id },
            onClose: { terminals.remove(session.id) },
            onRename: { newTitle in terminals.rename(id: session.id, title: newTitle) },
            onApproveApproval: pendingApproval.map { ap in
                { claudeService.approve(ap) }
            },
            onDenyApproval: pendingApproval.map { ap in
                { claudeService.deny(ap) }
            },
            onDismissApproval: pendingApproval.map { ap in
                { claudeService.dismissApproval(ap) }
            }
        )
        .padding(.horizontal, NarcSpacing.sm)
    }

    /// Vertical offset applied to a non-dragged row to create the insertion
    /// gap. When the user drags a tab over position `dropTargetIndex`, rows
    /// between the source and target shift by one row height.
    private func dragGapOffset(for idx: Int) -> CGFloat {
        guard let dragId = terminals.draggingSessionId,
              let sourceIdx = terminals.sessions.firstIndex(where: { $0.id == dragId }),
              let target = terminals.dropTargetIndex,
              sourceIdx != target
        else { return 0 }

        if target < sourceIdx {
            // Dragging upward — rows in [target, sourceIdx-1] shift down
            return (idx >= target && idx < sourceIdx) ? Self.tabRowHeight : 0
        } else {
            // Dragging downward — rows in [sourceIdx+1, target] shift up
            return (idx > sourceIdx && idx <= target) ? -Self.tabRowHeight : 0
        }
    }

    private var leftColumn: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(terminals.sessions.enumerated()), id: \.element.id) { idx, session in
                        let isDragging = terminals.draggingSessionId == session.id

                        makeTabRow(session: session, idx: idx)
                            .opacity(isDragging ? 0.25 : 1.0)
                            .offset(y: isDragging ? 0 : dragGapOffset(for: idx))
                            .zIndex(isDragging ? 100 : 0)
                            .gesture(
                                DragGesture(minimumDistance: 6)
                                    .onChanged { value in
                                        if terminals.draggingSessionId == nil {
                                            terminals.beginDrag(session.id)
                                        }
                                        let raw = (CGFloat(idx) * Self.tabRowHeight + value.translation.height)
                                            / Self.tabRowHeight
                                        let clamped = max(
                                            0,
                                            min(CGFloat(terminals.sessions.count - 1), raw.rounded())
                                        )
                                        terminals.updateDrag(
                                            translation: value.translation,
                                            targetIndex: Int(clamped)
                                        )
                                    }
                                    .onEnded { value in
                                        let moved = abs(value.translation.height) >= 4
                                            || abs(value.translation.width) >= 10
                                        terminals.endDrag(commit: moved)
                                    }
                            )
                            .animation(.narcSnap, value: terminals.dropTargetIndex)
                    }
                }
                .padding(.vertical, NarcSpacing.xs)
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            listContentWidth = geo.size.width
                        }.onChange(of: geo.size.width) { _, w in
                            listContentWidth = w
                        }
                    }
                )
            }

            // Floating drag preview — rendered at the ZStack level so it
            // overlays the ScrollView and is never clipped by the content area.
            // Constrained to the measured VStack width so the preview doesn't
            // expand to fill the ZStack (TerminalTabRow has Spacer() inside).
            if let draggingId = terminals.draggingSessionId,
               let draggedIdx = terminals.sessions.firstIndex(where: { $0.id == draggingId })
            {
                makeTabRow(session: terminals.sessions[draggedIdx], idx: draggedIdx)
                    .frame(width: tabDragPreviewWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(0.92)
                    .softShadow("lg")
                    .offset(terminals.draggingTranslation)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.narcBackground.opacity(0.6))
    }

    // MARK: - Right Column (Active terminal + file panel + diff overlay)

    private var selectedSession: OwnedSession? {
        terminals.sessions.first { $0.id == terminals.selectedId }
    }

    @ViewBuilder
    private var rightColumn: some View {
        if terminals.sessions.isEmpty {
            emptyState
        } else {
            terminalPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.narcBackground)
                .overlay(alignment: .trailing) {
                    if diffFile != nil, showDiffDrawer {
                        diffDrawer
                            .frame(width: 460)
                            .background(Color.narcBackground)
                            .overlay(Rectangle().frame(width: 0.5).foregroundColor(.narcBorder), alignment: .leading)
                            .shadow(color: .black.opacity(0.12), radius: 16, x: -4)
                            .transition(.move(edge: .trailing))
                    }
                }
                .animation(.narcSoft, value: showDiffDrawer)
        }
    }

    /// The terminal ZStack (factored out so it can be used in both layouts).
    /// Each session's PTY runs continuously in a ZStack; only the selected one
    /// is visible and interactive. The explicit `.frame(maxWidth:maxHeight:)`
    /// is critical — without it the ZStack sizes to its children's intrinsic
    /// sizes, which for an NSViewRepresentable-backed terminal can collapse to
    /// zero and disable scrolling entirely.
    private var terminalPane: some View {
        ZStack {
            ForEach(terminals.sessions) { session in
                TerminalPaneView(
                    executable: session.executable,
                    args: session.args,
                    cwd: session.cwd,
                    narcSessionId: session.id.uuidString,
                    isSelected: session.id == terminals.selectedId,
                    fontSize: terminalFontSize,
                    onExit: { _ in terminals.markDead(session.id) },
                    onTitleChange: { title in terminals.updateAutoTitle(id: session.id, title: title) },
                    onCwdChange: { cwd in terminals.updateCwd(id: session.id, cwd: cwd) },
                    onRegisterTerminate: { callback in
                        terminals.registerTerminateCallback(for: session.id, callback)
                    },
                    sessionLogURL: TerminalSessionManager.logURL(for: session.id)
                )
                .opacity(session.id == terminals.selectedId ? 1 : 0)
                .allowsHitTesting(session.id == terminals.selectedId)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Right-side diff overlay drawer.
    private var diffDrawer: some View {
        VStack(spacing: 0) {
            // ── Header ──
            HStack(spacing: NarcSpacing.sm) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.narcAccent)
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
                Button {
                    if let p = diffFile?.path { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.plain).help("在编辑器打开")
                Button { showDiffDrawer = false } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain).help("关闭")
            }
            .padding(.horizontal, NarcSpacing.md).padding(.vertical, NarcSpacing.sm)
            .background(Color.narcSurfaceMuted.opacity(0.6))
            Divider()

            // ── Body ──
            if diffLoading {
                VStack {
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                    Text("读取 git diff…").font(.narcCaption).foregroundColor(.narcTextMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = diffEmptyMessage {
                VStack(spacing: NarcSpacing.sm) {
                    Spacer()
                    Image(systemName: "doc.text").font(.system(size: 28)).foregroundColor(.narcTextFaint)
                    Text(msg).font(.narcCaption).foregroundColor(.narcTextMuted).multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiffRowsView(rows: diffRows)
            }
        }
    }

    // MARK: - Diff Helpers

    private func breadcrumb(_ path: String?) -> String {
        guard let path = path else { return "" }
        let dir = (path as NSString).deletingLastPathComponent
        let home = NSHomeDirectory()
        if dir == home { return "~" }
        if dir.hasPrefix(home + "/") { return "~" + dir.dropFirst(home.count) }
        return dir
    }

    private func summaryPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.narcMonoTiny)
            .foregroundColor(color)
            .padding(.horizontal, NarcSpacing.xs)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: NarcSpacing.md) {
            Spacer()
            Image(systemName: "terminal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.narcTextMuted)
            Text("还没有终端")
                .font(.narcSubtitle)
                .foregroundStyle(Color.narcText)
            Text("点击右上角「新建终端」开始")
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)
            Button(action: spawnShell) {
                HStack(spacing: NarcSpacing.xs) {
                    Image(systemName: "plus.circle.fill")
                    Text("新建终端")
                        .font(.narcCaption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, NarcSpacing.lg)
                .padding(.vertical, NarcSpacing.sm)
                .background(Capsule().fill(Color.narcAccent))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.narcBackground)
    }

    // MARK: - Spawn

    private func spawnShell() {
        let cwd = NSHomeDirectory()
        let id = terminals.newSession(cwd: cwd)
        terminals.selectedId = id
    }
}

// MARK: - Tab Row

/// Left-column row for one terminal session. Shows:
/// - status dot (alive/exited)
/// - title (rename via double-click or pencil button)
/// - cwd (auto-tracked via OSC 7, shortened with ~)
/// - hover-revealed pencil + ✕ buttons
struct TerminalTabRow: View {
    let session: OwnedSession
    let isSelected: Bool
    /// When this tab has a pending approval, the approval is threaded in here
    /// so the row can render a ⚠️ button that pops over an inline approval
    /// card (Allow / Deny / handle-in-terminal). nil = no popover button.
    var approval: PendingApproval?
    var onTap: () -> Void
    var onClose: () -> Void
    var onRename: (String) -> Void
    /// Triggered when the user taps Allow inside the popover.
    var onApproveApproval: (() -> Void)?
    /// Triggered when the user taps Deny inside the popover.
    var onDenyApproval: (() -> Void)?
    /// Triggered when the user picks "在终端处理" — closes the popover and
    /// hands control back to the CLI prompt.
    var onDismissApproval: (() -> Void)?

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var attentionPulse = false
    @State private var showApprovalPopover = false
    @State private var workingPulse = false
    @FocusState private var titleFieldFocused: Bool

    private var isWorking: Bool {
        guard let s = session.claude?.status else { return false }
        return s == .processing || s == .runningTool || s == .compacting
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left attention bar — slim vertical accent for needs-attention
            // tabs. This is the primary "look here" cue per the design
            // decision that the sidebar is the only notification surface.
            attentionBar

            HStack(alignment: .top, spacing: NarcSpacing.sm) {
                // Status dot — claude state if known, else alive/dead.
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                    .opacity(isWorking ? (workingPulse ? 1.0 : 0.45) : 1.0)
                    .animation(isWorking ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : nil,
                               value: workingPulse)
                    .padding(.top, 5)
                    .onAppear { if isWorking { workingPulse = true } }
                    .onChange(of: isWorking) { _, w in workingPulse = w }

                VStack(alignment: .leading, spacing: 2) {
                    titleLine
                    metaLine
                    claudeBadge
                }

                Spacer(minLength: 0)

                if let approval = approval {
                    // Approval pending → always-visible ⚠️ button so the user
                    // can pop the inline decision card without first hovering.
                    approvalButton(approval: approval)
                } else if isHovering && !isEditing {
                    actionButtons
                } else if session.hasUnseenChange && !isSelected {
                    // Unseen indicator — appears when the claude state
                    // changed while user was on a different tab. Cleared
                    // automatically by TerminalSessionManager.selectedId
                    // when the user switches to this tab.
                    unseenDot
                }
            }
            .padding(.horizontal, NarcSpacing.md)
            .padding(.vertical, NarcSpacing.sm)
        }
        .softRowBackground(isSelected: isSelected, needsAttention: needsAttention, isHovering: isHovering)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if !isEditing { onTap() }
        }
        .onAppear {
            if needsAttention { attentionPulse.toggle() }
        }
        .onChange(of: needsAttention) { _, nowAttention in
            if nowAttention { attentionPulse.toggle() }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var attentionBar: some View {
        if needsAttention {
            // v5.5 — red attention bar, 3pt wide, 6pt top/bottom inset,
            // pulsing to draw the eye to waiting-approval tabs.
            Rectangle()
                .fill(Color.narcDanger)
                .frame(width: 3)
                .padding(.vertical, 6)
                .opacity(attentionPulse ? 1.0 : 0.4)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: attentionPulse
                )
        } else if isSelected {
            // v5.5 — accent bar for the selected row, same geometry as above
            // but static (no pulse) and in the system accent colour.
            Rectangle()
                .fill(Color.narcAccent)
                .frame(width: 3)
                .padding(.vertical, 6)
        } else {
            // Reserve the same 3pt gutter so titles never shift horizontally
            // when a tab toggles between attention / selected / default states.
            Color.clear.frame(width: 3)
        }
    }

    private var unseenDot: some View {
        Circle()
            .fill(Color.narcDanger)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
            )
            .help("此标签页在你离开后状态有变化")
    }

    /// Always-visible ⚠️ button for tabs with a pending approval. Tapping
    /// pops a `ApprovalPopover` anchored to the right edge of the sidebar
    /// so the user can read the full tool / command without leaving the
    /// Workspace and act inline.
    private func approvalButton(approval: PendingApproval) -> some View {
        Button {
            showApprovalPopover.toggle()
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.narcDanger)
        }
        .buttonStyle(.plain)
        .help("查看 / 处理审批")
        .popover(isPresented: $showApprovalPopover, arrowEdge: .trailing) {
            ApprovalPopoverContent(
                approval: approval,
                projectLabel: ClaudeProjectName.from(cwd: approval.cwd),
                onAllow: {
                    showApprovalPopover = false
                    onApproveApproval?()
                },
                onDeny: {
                    showApprovalPopover = false
                    onDenyApproval?()
                },
                onHandleInTerminal: {
                    showApprovalPopover = false
                    onDismissApproval?()
                }
            )
        }
    }

    @ViewBuilder
    private var titleLine: some View {
        if isEditing {
            TextField("Title", text: $editText)
                .textFieldStyle(.plain)
                .font(.narcCaption)
                .foregroundStyle(Color.narcText)
                .focused($titleFieldFocused)
                .onSubmit { commitEdit() }
                .onExitCommand { cancelEdit() }
                .padding(.vertical, 1)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: NarcRadius.xs)
                        .fill(Color.narcSurfaceMuted)
                )
        } else {
            Text(session.displayTitle)
                .font(.narcCaption)
                .fontWeight(.medium)
                .foregroundStyle(session.isAlive ? Color.narcText : Color.narcTextMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .onTapGesture(count: 2) { startEdit() }
        }
    }

    private var metaLine: some View {
        HStack(spacing: NarcSpacing.xs) {
            if let cwd = session.cwd, !cwd.isEmpty {
                Text(shortCwd(cwd))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.narcTextMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            Text(timeAgo(session.creationDate))
                .font(.system(size: 10))
                .foregroundStyle(Color.narcTextFaint)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: NarcSpacing.xs) {
            Button(action: startEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.narcTextMuted)
            }
            .buttonStyle(.plain)
            .help("重命名（双击标题也可以）")

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.narcTextMuted)
            }
            .buttonStyle(.plain)
            .help("关闭终端")
        }
    }

    /// True when the tab should grab the user's attention (waiting for approval,
    /// recently errored, idle waiting for input). Drives the red row tint.
    private var needsAttention: Bool {
        guard let claude = session.claude else { return false }
        switch claude.status {
        case .waitingForApproval: return true
        default: return false
        }
    }

    /// Optional row showing the live claude state (icon + short label).
    @ViewBuilder
    private var claudeBadge: some View {
        if let claude = session.claude {
            HStack(spacing: NarcSpacing.xs) {
                Text(claudeBadgeIcon(claude.status))
                    .font(.system(size: 10))
                Text(claudeBadgeText(claude))
                    .font(.system(size: 10))
                    .foregroundStyle(claudeBadgeColor(claude.status))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.top, 1)
        }
    }

    private func claudeBadgeIcon(_ status: ClaudeStatus) -> String {
        // 3-bucket model per product decision: processing / waiting-input /
        // waiting-approval. Subtle differentiation inside "processing" via
        // emoji (thinking vs tool vs compacting), but the same color.
        switch status {
        case .processing:           return "⏳"
        case .runningTool:          return "→"
        case .compacting:           return "🗜"
        case .waitingForApproval:   return "⚠️"
        case .waitingForInput:      return "💬"
        case .ended:                return "■"
        case .unknown:              return "·"
        }
    }

    private func claudeBadgeText(_ claude: ClaudeSession) -> String {
        // Subtitle reads as "what is claude doing right now" — gives the
        // user the info they need to decide whether to interrupt.
        switch claude.status {
        case .processing:
            return "思考中"
        case .runningTool:
            // Show the live tool name so the user sees "Bash" / "Edit: foo.swift"
            // rather than a generic "running tool". Falls back to short label
            // if the tool isn't known yet (race between hook events).
            if let tool = claude.currentTool, !tool.isEmpty {
                return Self.shortToolLabel(tool: tool, input: claude.toolInput)
            }
            return "运行工具"
        case .compacting:
            return "压缩上下文"
        case .waitingForApproval:
            if let tool = claude.currentTool { return "待审批: \(tool)" }
            return "待审批"
        case .waitingForInput:
            return "等待输入"
        case .ended:
            return "已结束"
        case .unknown:
            return "—"
        }
    }

    /// Compact one-line description of a running tool. Mirrors what the
    /// Dashboard right-pane scrollback would say.
    private static func shortToolLabel(tool: String, input: [String: Any]?) -> String {
        if tool == "Bash", let cmd = input?["command"] as? String {
            let trimmed = cmd.count > 32 ? String(cmd.prefix(32)) + "…" : cmd
            return "Bash: \(trimmed)"
        }
        if (tool == "Edit" || tool == "Write" || tool == "Read"),
           let path = input?["file_path"] as? String {
            return "\(tool): \((path as NSString).lastPathComponent)"
        }
        return tool
    }

    private func claudeBadgeColor(_ status: ClaudeStatus) -> Color {
        // 3-bucket color model:
        //  - blue  = "claude is working" (processing / runningTool / compacting)
        //  - green = "claude is waiting for you to do something light" (waitingForInput)
        //  - red   = "claude needs explicit decision" (waitingForApproval)
        // ended/unknown are de-emphasized (gray).
        switch status {
        case .waitingForApproval:                            return .narcDanger
        case .processing, .runningTool, .compacting:         return .narcAccent
        case .waitingForInput:                               return .narcSuccess
        case .ended, .unknown:                               return .narcTextFaint
        }
    }

    private var statusDotColor: Color {
        if let claude = session.claude {
            return claudeBadgeColor(claude.status)
        }
        return session.isAlive ? .narcSuccess : .narcTextFaint
    }

    // MARK: - Edit lifecycle

    private func startEdit() {
        editText = session.userTitle ?? session.displayTitle
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            titleFieldFocused = true
        }
    }

    private func commitEdit() {
        onRename(editText)
        isEditing = false
        titleFieldFocused = false
    }

    private func cancelEdit() {
        isEditing = false
        titleFieldFocused = false
    }

    // MARK: - Formatting

    private func shortCwd(_ cwd: String) -> String {
        let home = NSHomeDirectory()
        if cwd == home { return "~" }
        if cwd.hasPrefix(home + "/") { return "~" + cwd.dropFirst(home.count) }
        return cwd
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

// MARK: - Approval Popover

/// Inline approval card popped from a tab's ⚠️ button. Shows the full tool
/// + command/file path, plus three action buttons (Allow / Deny / handle in
/// terminal). All three close the popover via the parent's binding.
///
/// `AskUserQuestion` / `Elicitation` / `SendUserMessage` are interactive
/// tools — Allow/Deny don't apply because the actual prompt happens inside
/// the terminal. For those we collapse to a single "去终端回答" button.
struct ApprovalPopoverContent: View {
    let approval: PendingApproval
    let projectLabel: String
    var onAllow: () -> Void
    var onDeny: () -> Void
    var onHandleInTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.md) {
            header
            commandBlock
            buttonRow
        }
        .padding(NarcSpacing.lg)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: NarcSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.narcDanger)
            VStack(alignment: .leading, spacing: 2) {
                Text("待审批")
                    .font(.narcSubtitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.narcText)
                HStack(spacing: NarcSpacing.xs) {
                    Text(projectLabel)
                        .font(.narcCaption)
                        .foregroundStyle(Color.narcTextMuted)
                    Text("·")
                        .foregroundStyle(Color.narcTextMuted)
                    Text(approval.tool)
                        .font(.narcCaption)
                        .foregroundStyle(Color.narcDanger)
                        .padding(.horizontal, NarcSpacing.xs)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.narcDanger.opacity(0.14))
                        )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var commandBlock: some View {
        ScrollView {
            Text(displayBody)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.narcText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NarcSpacing.sm)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: NarcRadius.sm)
                .fill(Color.narcSurfaceMuted)
        )
    }

    @ViewBuilder
    private var buttonRow: some View {
        if approval.isPermissionRequest {
            HStack(spacing: NarcSpacing.sm) {
                Button(action: onAllow) {
                    Text("允许")
                        .font(.narcCaption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NarcSpacing.sm)
                        .background(Capsule().fill(Color.narcSuccess))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return)

                Button(action: onDeny) {
                    Text("拒绝")
                        .font(.narcCaption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NarcSpacing.sm)
                        .background(Capsule().fill(Color.narcDanger))
                }
                .buttonStyle(.plain)

                Button(action: onHandleInTerminal) {
                    Text("去终端处理")
                        .font(.narcCaption)
                        .foregroundStyle(Color.narcTextMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NarcSpacing.sm)
                        .background(
                            Capsule().strokeBorder(Color.narcBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        } else {
            // Interactive tools (AskUserQuestion / Elicitation / SendUserMessage)
            // — Allow/Deny make no semantic sense, only "go answer in the terminal".
            Button(action: onHandleInTerminal) {
                Text("去终端回答")
                    .font(.narcCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NarcSpacing.sm)
                    .background(Capsule().fill(Color.narcAccent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return)
        }
    }

    private var displayBody: String {
        // Bash → full command. Edit/Write/Read → file path. Everything else
        // → tool input as JSON-ish summary.
        if approval.tool == "Bash", let input = approval.toolInput,
           let cmd = input["command"] as? String {
            return cmd
        }
        if let input = approval.toolInput,
           let path = input["file_path"] as? String {
            return path
        }
        if let input = approval.toolInput {
            return input.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        }
        return approval.commandDescription
    }
}

// MARK: - File Change Popover

/// Popover content listing files Claude has touched in the current session.
/// Each row shows the tool icon + file path. Click a row to open its diff.
struct FileChangePopover: View {
    let files: [FileChange]
    var selectedPath: String? = nil
    var fileStats: [String: (added: Int, removed: Int)] = [:]
    var onFileTap: ((FileChange) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: NarcSpacing.xs) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundColor(.narcTextMuted)
                Text("最近文件变更")
                    .font(.narcCaption)
                    .fontWeight(.medium)
                    .foregroundColor(.narcText)
                Spacer()
                Text("\(files.count)")
                    .font(.narcMonoTiny)
                    .foregroundColor(.narcTextMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.narcSurfaceMuted))
            }
            .padding(.horizontal, NarcSpacing.md)
            .padding(.vertical, NarcSpacing.sm - 2)

            Divider()

            if files.isEmpty {
                VStack(spacing: NarcSpacing.xs) {
                    Spacer()
                    Text("暂无文件变更")
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)
                    Text("Claude 执行 Edit / Write 后这里会列出改动的文件")
                        .font(.system(size: 10))
                        .foregroundColor(.narcTextFaint)
                    Spacer()
                }
                .frame(height: 100)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.offset) { idx, change in
                            FileChangeRow(
                                change: change,
                                isSelected: selectedPath == change.path,
                                added: fileStats[change.path]?.added,
                                removed: fileStats[change.path]?.removed
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onFileTap?(change) }
                            if idx < files.count - 1 {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                    .padding(.vertical, NarcSpacing.xxs)
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 320)
    }
}

private struct FileChangeRow: View {
    let change: FileChange
    var isSelected: Bool = false
    var added: Int? = nil
    var removed: Int? = nil

    private var toolIcon: Image {
        switch change.tool {
        case "Edit":  return Image(systemName: "pencil")
        case "Write": return Image(systemName: "plus.square")
        case "Read":  return Image(systemName: "eye")
        default:      return Image(systemName: "arrow.right")
        }
    }

    private var fileName: String {
        (change.path as NSString).lastPathComponent
    }

    private var directory: String {
        let dir = (change.path as NSString).deletingLastPathComponent
        let home = NSHomeDirectory()
        if dir == home { return "~" }
        if dir.hasPrefix(home + "/") { return "~" + dir.dropFirst(home.count) }
        return dir
    }

    var body: some View {
        HStack(spacing: NarcSpacing.sm) {
            toolIcon
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .narcAccent : .narcTextMuted)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.narcCaption)
                    .foregroundColor(.narcText)
                    .lineLimit(1)
                Text(directory)
                    .font(.system(size: 10))
                    .foregroundColor(.narcTextMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            // Diff stat pills
            if let added = added, added > 0 {
                Text("+\(added)")
                    .font(.narcMonoTiny)
                    .foregroundColor(.narcSuccess)
                    .padding(.horizontal, NarcSpacing.xs)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.narcSuccess.opacity(0.12)))
            }
            if let removed = removed, removed > 0 {
                Text("−\(removed)")
                    .font(.narcMonoTiny)
                    .foregroundColor(.narcDanger)
                    .padding(.horizontal, NarcSpacing.xs)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.narcDanger.opacity(0.12)))
            }

            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: change.path)])
            }) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
                    .foregroundColor(.narcTextMuted)
            }
            .buttonStyle(.plain)
            .help("在 Finder 中显示")
        }
        .padding(.horizontal, NarcSpacing.md)
        .padding(.vertical, NarcSpacing.xs + 1)
        .softRowBackground(isSelected: isSelected, needsAttention: false, isHovering: false)
    }
}

// MARK: - Diff Row Types & Parser

struct DiffRow: Identifiable {
    enum Kind { case context, add, del, gap }
    let id = UUID()
    let kind: Kind
    let oldNum: Int?
    let newNum: Int?
    let text: String
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

    private static func hunkStarts(_ s: String) -> (Int, Int) {
        var o = 0, n = 0
        for p in s.split(separator: " ") {
            if p.hasPrefix("-") { o = Int(p.dropFirst().split(separator: ",").first ?? "") ?? 0 }
            else if p.hasPrefix("+") { n = Int(p.dropFirst().split(separator: ",").first ?? "") ?? 0 }
        }
        return (o, n)
    }
}

// MARK: - Diff Rows View

struct DiffRowsView: View {
    let rows: [DiffRow]

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    DiffRowCell(row: row)
                }
            }
        }
        .background(Color.narcBackground)
    }
}

private struct DiffRowCell: View {
    let row: DiffRow

    var body: some View {
        switch row.kind {
        case .gap:
            HStack(spacing: 0) {
                Rectangle().fill(Color.narcBorder).frame(height: 1).frame(width: 36)
                Text(row.text)
                    .font(.narcMonoSmall)
                    .foregroundColor(.narcTextFaint)
                Rectangle().fill(Color.narcBorder).frame(height: 1)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, NarcSpacing.sm)
            .background(Color.narcSurfaceMuted.opacity(0.5))

        case .context:
            HStack(spacing: 0) {
                lineNumView(row.oldNum).frame(width: 38, alignment: .trailing)
                lineNumView(row.newNum).frame(width: 38, alignment: .trailing)
                Text(row.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.narcText)
            }
            .padding(.horizontal, 2)

        case .add:
            HStack(spacing: 0) {
                Color.clear.frame(width: 38)
                lineNumView(row.newNum).frame(width: 38, alignment: .trailing)
                Text("+")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.narcSuccess)
                Text(row.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.narcSuccess)
            }
            .padding(.horizontal, 2)
            .background(Color.narcSuccess.opacity(0.10))

        case .del:
            HStack(spacing: 0) {
                lineNumView(row.oldNum).frame(width: 38, alignment: .trailing)
                Color.clear.frame(width: 38)
                Text("−")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.narcDanger)
                Text(row.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.narcDanger)
            }
            .padding(.horizontal, 2)
            .background(Color.narcDanger.opacity(0.10))
        }
    }

    private func lineNumView(_ num: Int?) -> some View {
        Text(num.map(String.init) ?? "")
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.narcTextFaint)
    }
}
