import Foundation

enum DevRuntimeOptions {
    /// UI-only dev mode: keep Workspace / terminal surfaces available, but do
    /// not touch Accessibility-dependent paths.
    static var noAX: Bool {
        envFlag("NARC_DEV_NO_AX")
    }

    /// Terminal-host dev mode: run as a raw Swift executable from the terminal,
    /// keep Accessibility-enabled features, and avoid presenting as a Dock app.
    static var terminalHost: Bool {
        envFlag("NARC_DEV_TERMINAL_HOST") || Bundle.main.bundleIdentifier == nil
    }

    private static func envFlag(_ key: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[key]?.lowercased() else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(raw)
    }
}
