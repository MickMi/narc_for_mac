import SwiftUI
import SwiftTerm
import AppKit

// MARK: - SwiftTerm subclass with smart-paste

/// Subclass of `LocalProcessTerminalView` that adds **⌘⇧C smart copy**.
///
/// When the user selects text in the terminal, a small bubble appears near the
/// selection. Tapping the bubble (or pressing ⌘⇧C) copies the selected text
/// with common leading whitespace stripped, so code pasted from Claude's output
/// lands clean. ⌘C still copies the original (indented) text.
final class NarcTerminalView: LocalProcessTerminalView {

    private var lastMouseUpInView: CGPoint = .zero
    // Strong ref — nothing else retains the controller (its `view` is held by the
    // superview via addSubview, but the view doesn't retain the controller back).
    // A weak ref would let the controller dealloc immediately, breaking the
    // "已复制" feedback / dismissal and stacking a new bubble on every selection.
    private var bubble: SmartCopyBubbleController?

    /// Intercept ⌘⇧C for smart copy, ⌘F for search, ⌘G for find-next, Esc for dismiss.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCmdShiftC = mods == [.command, .shift]
            && event.charactersIgnoringModifiers?.lowercased() == "c"
        let isCmdF = mods == [.command]
            && event.charactersIgnoringModifiers?.lowercased() == "f"
        let isCmdG = mods == [.command]
            && event.charactersIgnoringModifiers?.lowercased() == "g"
        let isCmdShiftG = mods == [.command, .shift]
            && event.charactersIgnoringModifiers?.lowercased() == "g"
        let isEscape = mods == []
            && event.keyCode == 53  // Esc

        if isCmdShiftC {
            performSmartCopy()
            return true
        }
        if isCmdF {
            showFindBar()
            return true
        }
        if isCmdG {
            performFindNext()
            return true
        }
        if isCmdShiftG {
            performFindPrevious()
            return true
        }
        if isEscape && findBar?.isHidden == false {
            hideFindBar()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Find Bar

    private var findBar: NSSearchField?
    private var findBarTopConstraint: NSLayoutConstraint?

    private func showFindBar() {
        if findBar == nil {
            let bar = NSSearchField(frame: .zero)
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.placeholderString = "搜索终端输出…"
            bar.sendsSearchStringImmediately = true
            bar.target = self
            bar.action = #selector(findBarSearchAction)
            addSubview(bar)
            NSLayoutConstraint.activate([
                bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                bar.widthAnchor.constraint(equalToConstant: 280),
            ])
            findBarTopConstraint = bar.topAnchor.constraint(equalTo: topAnchor, constant: 8)
            findBarTopConstraint?.isActive = true
            findBar = bar
        }
        findBar?.isHidden = false
        findBar?.stringValue = ""
        // Pre-fill with current selection if any
        if let sel = getSelection(), !sel.isEmpty {
            let firstLine = sel.components(separatedBy: "\n").first ?? sel
            findBar?.stringValue = String(firstLine.prefix(80))
        }
        // Make the search field first responder
        window?.makeFirstResponder(findBar)
    }

    private func hideFindBar() {
        findBar?.isHidden = true
        clearSearch()
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self)
        }
    }

    @objc private func findBarSearchAction() {
        guard let term = findBar?.stringValue, !term.isEmpty else {
            clearSearch()
            return
        }
        _ = findNext(term, scrollToResult: true)
    }

    private func performFindNext() {
        guard let term = findBar?.stringValue, !term.isEmpty else {
            // Fall back to find pasteboard (standard macOS ⌘G behavior)
            if let pbTerm = NSPasteboard(name: .find).string(forType: .string), !pbTerm.isEmpty {
                _ = findNext(pbTerm, scrollToResult: true)
            }
            return
        }
        _ = findNext(term, scrollToResult: true)
    }

    private func performFindPrevious() {
        guard let term = findBar?.stringValue, !term.isEmpty else {
            if let pbTerm = NSPasteboard(name: .find).string(forType: .string), !pbTerm.isEmpty {
                _ = findPrevious(pbTerm, scrollToResult: true)
            }
            return
        }
        _ = findPrevious(term, scrollToResult: true)
    }

    /// Copy selected text → dedent → system clipboard.
    private func performSmartCopy() {
        guard let raw = getSelection(), !raw.isEmpty else { return }
        let dedented = NarcTerminalView.dedent(raw)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(dedented, forType: .string)
        bubble?.showCopied()
    }

    /// Strip the minimum common leading-space indent from every non-blank
    /// line. Tabs are treated as a single column (we don't try to be clever
    /// about tab-width — most editors ship with space-indent default).
    /// Blank / whitespace-only lines are preserved verbatim so trailing
    /// blank lines in code blocks don't get rewritten.
    static func dedent(_ s: String) -> String {
        let lines = s.components(separatedBy: "\n")
        let nonBlank = lines.filter { !$0.allSatisfy({ $0 == " " || $0 == "\t" }) }
        guard !nonBlank.isEmpty else { return s }

        let leading = nonBlank.map { line -> Int in
            var n = 0
            for ch in line {
                if ch == " " { n += 1 } else { break }
            }
            return n
        }
        let minIndent = leading.min() ?? 0
        guard minIndent > 0 else { return s }

        return lines.map { line -> String in
            if line.allSatisfy({ $0 == " " || $0 == "\t" }) { return line }
            // Safe because every non-blank line has at least minIndent leading spaces.
            return String(line.dropFirst(minIndent))
        }.joined(separator: "\n")
    }

    // MARK: - Selection bubble

    private var mouseMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = window {
            if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                guard let self = self, let win = self.window, event.window === win else { return event }
                self.lastMouseUpInView = self.convert(event.locationInWindow, from: nil)
                return event
            }
            // Dismiss the smart-copy bubble when the window loses key
            // (user switches to another app or closes a popover).
            if resignKeyObserver == nil {
                resignKeyObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: w,
                    queue: .main
                ) { [weak self] _ in
                    self?.dismissBubble()
                }
            }
            installScrollMonitor()
        } else {
            if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
            if let o = resignKeyObserver { NotificationCenter.default.removeObserver(o); resignKeyObserver = nil }
            removeScrollMonitor()
        }
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

    private func showOrMoveBubble(near point: CGPoint) {
        let ctrl = bubble ?? {
            let c = SmartCopyBubbleController(onCopy: { [weak self] in self?.performSmartCopy() })
            addSubview(c.view)
            bubble = c
            return c
        }()
        ctrl.position(near: point, in: bounds)
    }

    private func dismissBubble() {
        bubble?.view.removeFromSuperview()
        bubble = nil
    }

    /// Dismiss the bubble when the terminal pane loses selection (tab switch).
    /// Called from `TerminalPaneView.updateNSView` when `isSelected` goes false.
    fileprivate func dismissBubbleIfNeeded() {
        if bubble != nil { dismissBubble() }
    }

    // MARK: - Scroll Forwarding

    /// SwiftUI may intercept scroll-wheel events before they reach the NSView.
    /// We capture them early and route them to the right owner:
    /// normal shell scrollback stays in SwiftTerm; alternate-screen TUI panes
    /// receive mouse-wheel events so their content area can scroll.
    private var scrollMonitor: Any?

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self,
                  let win = self.window,
                  event.window === win,
                  self.ownsScrollEvent(event, in: win)
            else { return event }

            let localPoint = self.convert(event.locationInWindow, from: nil)
            if !self.forwardWheelToAlternateScreen(event, at: localPoint) {
                self.scrollWheel(with: event)
            }
            return nil  // Consume so SwiftUI doesn't re-route it.
        }
    }

    private func removeScrollMonitor() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
    }

    private func ownsScrollEvent(_ event: NSEvent, in window: NSWindow) -> Bool {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(localPoint) else { return false }

        guard let contentView = window.contentView else { return true }
        let contentPoint = contentView.convert(event.locationInWindow, from: nil)
        guard let hitView = contentView.hitTest(contentPoint) else { return false }

        return hitView === self || hitView.isDescendant(of: self)
    }

    private func forwardWheelToAlternateScreen(_ event: NSEvent, at localPoint: CGPoint) -> Bool {
        guard event.deltaY != 0,
              terminal.isCurrentBufferAlternate,
              terminal.mouseMode != .off
        else { return false }

        let dims = terminal.getDims()
        guard dims.cols > 0, dims.rows > 0, bounds.width > 0, bounds.height > 0 else { return true }

        let cellWidth = max(bounds.width / CGFloat(dims.cols), 1)
        let cellHeight = max(bounds.height / CGFloat(dims.rows), 1)
        let col = max(0, min(dims.cols - 1, Int(localPoint.x / cellWidth)))
        let row = max(0, min(dims.rows - 1, Int((bounds.height - localPoint.y) / cellHeight)))
        let pixelX = max(1, min(Int(bounds.width), Int(localPoint.x.rounded())))
        let pixelY = max(1, min(Int(bounds.height), Int((bounds.height - localPoint.y).rounded())))

        let magnitude = max(abs(event.deltaY), abs(event.scrollingDeltaY) / 12)
        let repeats = max(1, min(8, Int(magnitude.rounded(.up))))
        let wheelUpButton = 64
        let wheelDownButton = 65
        let button = event.deltaY > 0 ? wheelUpButton : wheelDownButton

        for _ in 0..<repeats {
            terminal.sendEvent(buttonFlags: button, x: col, y: row, pixelX: pixelX, pixelY: pixelY)
        }
        return true
    }
}

// MARK: - SwiftUI wrapper

/// SwiftUI wrapper around SwiftTerm's `LocalProcessTerminalView`.
/// Forks the given executable with a PTY and renders xterm-compatible output.
///
/// MVP: starts the process on `makeNSView`, calls `onExit` when it dies.
/// Future: hook input recording, `.signal(SIGTERM)` from a kill button, scroll-buffer
/// export, etc.
struct TerminalPaneView: NSViewRepresentable {
    let executable: String
    let args: [String]
    let cwd: String?
    /// Stamped into the child's env as `NARC_SESSION_ID`. The narc-hook script
    /// reads this and includes it on the socket payload, so workspace tabs
    /// can be matched to the hook events without relying on tty.
    let narcSessionId: String
    /// True when this pane is the active one in the dashboard. We use this to
    /// route keyboard focus (first responder) to the correct SwiftTerm view —
    /// without it, the user would see the terminal but be unable to type.
    let isSelected: Bool
    /// Terminal font size in points. Default 13.
    let fontSize: CGFloat
    let onExit: ((Int32?) -> Void)?
    let onTitleChange: ((String) -> Void)?
    let onCwdChange: ((String?) -> Void)?
    /// Called once in `makeNSView` with a closure that kills the underlying PTY.
    /// The parent (DashboardView) wires this to `TerminalSessionManager` so
    /// `terminateAll()` can kill all sessions at once.
    let onRegisterTerminate: (((@escaping () -> Void)) -> Void)?
    /// Where to write the terminal log on process exit. nil disables logging.
    let sessionLogURL: URL?

    init(
        executable: String = "/bin/zsh",
        args: [String] = ["-l"],
        cwd: String? = nil,
        narcSessionId: String,
        isSelected: Bool = true,
        fontSize: CGFloat = 13,
        onExit: ((Int32?) -> Void)? = nil,
        onTitleChange: ((String) -> Void)? = nil,
        onCwdChange: ((String?) -> Void)? = nil,
        onRegisterTerminate: (((@escaping () -> Void)) -> Void)? = nil,
        sessionLogURL: URL? = nil
    ) {
        self.executable = executable
        self.args = args
        self.cwd = cwd
        self.narcSessionId = narcSessionId
        self.isSelected = isSelected
        self.fontSize = fontSize
        self.onExit = onExit
        self.onTitleChange = onTitleChange
        self.onCwdChange = onCwdChange
        self.onRegisterTerminate = onRegisterTerminate
        self.sessionLogURL = sessionLogURL
    }

    func makeNSView(context: Context) -> NarcTerminalView {
        // Use a reasonable default frame so the PTY starts with usable dimensions.
        // SwiftUI will override this once layout completes, but without it the
        // terminal can start at 0×0, which collapses the NSScrollView and
        // effectively disables scrolling even after resize.
        let term = NarcTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        term.processDelegate = context.coordinator
        term.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Bind background/foreground to system semantic colors so the terminal
        // blends into the workspace chrome (and follows light/dark mode). The
        // ANSI 16-color palette stays at SwiftTerm's default — git/claude
        // colored output is preserved. Themed palette is a follow-up task.
        term.nativeBackgroundColor = NSColor.windowBackgroundColor
        term.nativeForegroundColor = NSColor.labelColor

        // Build environment: inherit user shell env, force xterm-256color for compat
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        // Tag this PTY with the workspace session ID so narc-hook can correlate
        // claude events back to this tab.
        env["NARC_SESSION_ID"] = narcSessionId

        // SwiftTerm wants env as ["KEY=VALUE", ...]
        let envArray = env.map { "\($0.key)=\($0.value)" }

        // Change to working dir before fork — child inherits cwd
        if let cwd = cwd, !cwd.isEmpty {
            FileManager.default.changeCurrentDirectoryPath(cwd)
        }

        term.startProcess(executable: executable, args: args, environment: envArray)

        // Register terminate callback — weak-captures the view so the callback
        // becomes a no-op if the view deallocs before terminateAll() fires.
        onRegisterTerminate?({ [weak term] in
            term?.terminate()
        })

        // Initial focus — once the view has joined a window, make it the first
        // responder so the user can type immediately. Deferred because the view
        // hasn't been added to a window yet at this point.
        DispatchQueue.main.async {
            term.window?.makeFirstResponder(term)
        }

        return term
    }

    func updateNSView(_ nsView: NarcTerminalView, context: Context) {
        // Update font size if it changed.
        if nsView.font.pointSize != fontSize {
            nsView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        // Re-focus when this pane becomes the selected one (tab switch).
        guard isSelected else {
            // Tab switched away — dismiss the smart-copy bubble so it doesn't
            // linger on a stale pane.
            nsView.dismissBubbleIfNeeded()
            return
        }
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if window.firstResponder !== nsView {
                window.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onExit: onExit, onTitleChange: onTitleChange, onCwdChange: onCwdChange, sessionLogURL: sessionLogURL)
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onExit: ((Int32?) -> Void)?
        let onTitleChange: ((String) -> Void)?
        let onCwdChange: ((String?) -> Void)?
        let sessionLogURL: URL?

        init(
            onExit: ((Int32?) -> Void)?,
            onTitleChange: ((String) -> Void)?,
            onCwdChange: ((String?) -> Void)?,
            sessionLogURL: URL?
        ) {
            self.onExit = onExit
            self.onTitleChange = onTitleChange
            self.onCwdChange = onCwdChange
            self.sessionLogURL = sessionLogURL
        }

        // MARK: - LocalProcessTerminalViewDelegate

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // PTY auto-resizes; nothing to do here for MVP.
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            DispatchQueue.main.async { [weak self] in
                self?.onTitleChange?(title)
            }
        }

        // The following two are inherited from `TerminalViewDelegate` (the base
        // protocol). SwiftTerm 1.2 declares them with `source: TerminalView`,
        // not `LocalProcessTerminalView` — match exactly or conformance fails.

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // SwiftTerm hands us the raw OSC 7 payload, which is shaped like
            // `file://hostname/path/to/dir`. Extract just the local path.
            let cleaned: String?
            if let dir = directory, !dir.isEmpty {
                if let url = URL(string: dir), url.scheme == "file" {
                    cleaned = url.path
                } else {
                    cleaned = dir
                }
            } else {
                cleaned = nil
            }
            DispatchQueue.main.async { [weak self] in
                self?.onCwdChange?(cleaned)
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            // Dump full terminal buffer to session log before marking dead.
            if let url = sessionLogURL {
                let dims = source.terminal.getDims()
                let start = Position(col: 0, row: 0)
                let end = Position(col: dims.cols, row: dims.rows)
                let text = source.terminal.getText(start: start, end: end)
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
            DispatchQueue.main.async { [weak self] in
                self?.onExit?(exitCode)
            }
        }
    }
}
