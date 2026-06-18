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

    /// Intercept ⌘⇧C for smart copy. ⌘C (original copy) is unaffected.
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let _ = window {
            if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                guard let self = self, let w = self.window, event.window === w else { return event }
                self.lastMouseUpInView = self.convert(event.locationInWindow, from: nil)
                return event
            }
        } else {
            if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
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
    let onExit: ((Int32?) -> Void)?
    let onTitleChange: ((String) -> Void)?
    let onCwdChange: ((String?) -> Void)?

    init(
        executable: String = "/bin/zsh",
        args: [String] = ["-l"],
        cwd: String? = nil,
        narcSessionId: String,
        isSelected: Bool = true,
        onExit: ((Int32?) -> Void)? = nil,
        onTitleChange: ((String) -> Void)? = nil,
        onCwdChange: ((String?) -> Void)? = nil
    ) {
        self.executable = executable
        self.args = args
        self.cwd = cwd
        self.narcSessionId = narcSessionId
        self.isSelected = isSelected
        self.onExit = onExit
        self.onTitleChange = onTitleChange
        self.onCwdChange = onCwdChange
    }

    func makeNSView(context: Context) -> NarcTerminalView {
        let term = NarcTerminalView(frame: .zero)
        term.processDelegate = context.coordinator
        term.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

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

        // Initial focus — once the view has joined a window, make it the first
        // responder so the user can type immediately. Deferred because the view
        // hasn't been added to a window yet at this point.
        DispatchQueue.main.async {
            term.window?.makeFirstResponder(term)
        }

        return term
    }

    func updateNSView(_ nsView: NarcTerminalView, context: Context) {
        // Re-focus when this pane becomes the selected one (tab switch).
        // SwiftUI calls updateNSView on every state change; we only act when
        // we're the newly active pane and we don't already hold focus.
        guard isSelected else { return }
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if window.firstResponder !== nsView {
                window.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onExit: onExit, onTitleChange: onTitleChange, onCwdChange: onCwdChange)
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onExit: ((Int32?) -> Void)?
        let onTitleChange: ((String) -> Void)?
        let onCwdChange: ((String?) -> Void)?

        init(
            onExit: ((Int32?) -> Void)?,
            onTitleChange: ((String) -> Void)?,
            onCwdChange: ((String?) -> Void)?
        ) {
            self.onExit = onExit
            self.onTitleChange = onTitleChange
            self.onCwdChange = onCwdChange
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
            DispatchQueue.main.async { [weak self] in
                self?.onExit?(exitCode)
            }
        }
    }
}
