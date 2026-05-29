import SwiftUI
import SwiftTerm
import AppKit

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
        isSelected: Bool = true,
        onExit: ((Int32?) -> Void)? = nil,
        onTitleChange: ((String) -> Void)? = nil,
        onCwdChange: ((String?) -> Void)? = nil
    ) {
        self.executable = executable
        self.args = args
        self.cwd = cwd
        self.isSelected = isSelected
        self.onExit = onExit
        self.onTitleChange = onTitleChange
        self.onCwdChange = onCwdChange
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let term = LocalProcessTerminalView(frame: .zero)
        term.processDelegate = context.coordinator
        term.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Build environment: inherit user shell env, force xterm-256color for compat
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }

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

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
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
            DispatchQueue.main.async { [weak self] in
                self?.onCwdChange?(directory)
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [weak self] in
                self?.onExit?(exitCode)
            }
        }
    }
}
