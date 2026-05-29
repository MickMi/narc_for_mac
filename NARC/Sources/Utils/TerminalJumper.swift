import Foundation
import AppKit

/// Pure utility for jumping to a Claude terminal window via AppleScript.
/// Picks Terminal.app or iTerm2 based on what is running, with last-resort fallback.
/// Matching priority: TTY (exact tab) > CWD in title > activate any terminal.
///
/// Extracted from AppDelegate so SwiftUI views can call it directly without
/// going through callback plumbing.
enum TerminalJumper {

    /// Jump to a terminal window matching the given TTY/CWD hint.
    /// Runs the AppleScript on a background queue to keep the UI responsive.
    static func jump(tty: String?, cwd: String?, projectName: String? = nil) {
        let ttyValue = tty ?? ""
        let cwdHint: String
        if let cwd = cwd, !cwd.isEmpty {
            cwdHint = (cwd as NSString).lastPathComponent
        } else if let project = projectName, !project.isEmpty, project != "?" {
            cwdHint = project
        } else {
            cwdHint = ""
        }

        let script: String
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first != nil {
            script = terminalScript(tty: ttyValue, cwdHint: cwdHint)
        } else if NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first != nil {
            script = itermScript(tty: ttyValue, cwdHint: cwdHint)
        } else {
            // Last resort: activate whichever terminal we can find
            let terminalBundles = [
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "net.kovidgoyal.kitty",
                "com.mitchellh.ghostty",
            ]
            for bundleID in terminalBundles {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                    app.activate()
                    return
                }
            }
            return
        }

        print("[NARC] 🔌 Jumping to terminal (tty=\(ttyValue.isEmpty ? "none" : ttyValue), cwd=\(cwdHint))")

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    print("[NARC] ⚠️ Jump script error: \(err)")
                }
            } catch {
                print("[NARC] ⚠️ Jump failed: \(error)")
            }
        }
    }

    /// AppleScript for Terminal.app — TTY exact match first, then CWD title fallback.
    private static func terminalScript(tty: String, cwdHint: String) -> String {
        return """
        tell application "Terminal"
            \(tty.isEmpty ? "-- TTY not available, skip" : """
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return
                    end if
                end repeat
            end repeat
            """)

            \(cwdHint.isEmpty ? "-- CWD hint not available, skip" : """
            repeat with w in windows
                if name of w contains "\(cwdHint)" then
                    set index of w to 1
                    activate
                    return
                end if
            end repeat
            """)

            activate
        end tell
        """
    }

    /// AppleScript for iTerm2 — TTY exact match first, then CWD title fallback.
    private static func itermScript(tty: String, cwdHint: String) -> String {
        return """
        tell application "iTerm2"
            \(tty.isEmpty ? "-- TTY not available, skip" : """
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select s
                            select t
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
            """)

            \(cwdHint.isEmpty ? "-- CWD hint not available, skip" : """
            repeat with w in windows
                if name of w contains "\(cwdHint)" then
                    set index of w to 1
                    activate
                    return
                end if
            end repeat
            """)

            activate
        end tell
        """
    }

    // MARK: - Spawn / Close (Dashboard support)

    /// Open a new iTerm2 window, cd to `cwd` if provided, and run `claude`.
    /// Falls back to Terminal.app if iTerm2 is not running.
    static func spawnClaude(cwd: String? = nil) {
        let cdLine = (cwd?.isEmpty == false) ? "cd \(shellEscape(cwd!)) && " : ""
        let claudeCommand = "\(cdLine)claude"

        let script: String
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first != nil {
            script = """
            tell application "iTerm2"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "\(claudeCommand)"
                end tell
            end tell
            """
        } else {
            // Terminal.app fallback
            script = """
            tell application "Terminal"
                activate
                do script "\(claudeCommand)"
            end tell
            """
        }

        runAppleScript(script, label: "spawn claude")
    }

    /// Close the iTerm2 session with the given TTY. Best-effort.
    /// If TTY is unknown or we can't find the session, this no-ops.
    /// The user can also Ctrl-D / `exit` in the terminal manually.
    static func closeSession(tty: String?) {
        guard let tty = tty, !tty.isEmpty else {
            print("[NARC] ⚠️ closeSession: missing tty")
            return
        }

        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            close s
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """

        runAppleScript(script, label: "close session")
    }

    // MARK: - Internals

    private static func runAppleScript(_ script: String, label: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    print("[NARC] ⚠️ \(label) script error: \(err)")
                } else {
                    print("[NARC] ✓ \(label)")
                }
            } catch {
                print("[NARC] ⚠️ \(label) failed: \(error)")
            }
        }
    }

    /// Single-quote-escape a path for safe inclusion in a shell command inside AppleScript.
    private static func shellEscape(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
