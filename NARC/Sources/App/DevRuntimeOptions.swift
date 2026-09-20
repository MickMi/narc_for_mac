import Foundation

enum AssistantStorageSelection: Equatable {
    case standard
    case temporary(URL)
    case invalidOverride
}

enum DevRuntimeOptions {
    /// UI-only dev mode: keep the product surfaces available, but do not touch
    /// Accessibility-dependent paths.
    static var noAX: Bool {
        envFlag("NARC_DEV_NO_AX")
    }

    /// Debug-only storage override for hands-on UI checks. Restrict it to a
    /// temporary directory so validation can never overwrite personal data.
    /// This is intentionally independent from `noAX`: selected-text QA needs
    /// real Accessibility access while still writing only isolated fixtures.
    static var assistantStorageSelection: AssistantStorageSelection {
        #if DEBUG
        return resolvedAssistantStorageSelection(
            rawPath: ProcessInfo.processInfo.environment[
                "NARC_DEV_ASSISTANT_STORAGE_PATH"
            ]
        )
        #else
        return .standard
        #endif
    }

    static func resolvedAssistantStorageSelection(
        rawPath: String?
    ) -> AssistantStorageSelection {
        guard rawPath != nil else { return .standard }
        guard let url = validatedAssistantStorageURL(rawPath: rawPath) else {
            return .invalidOverride
        }
        return .temporary(url)
    }

    static func validatedAssistantStorageURL(
        rawPath: String?,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> URL? {
        guard let rawPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty,
              rawPath.hasPrefix("/") else {
            return nil
        }

        let fileManager = FileManager.default
        let lexicalCandidate = URL(fileURLWithPath: rawPath, isDirectory: false)
            .standardizedFileURL
        let parent = lexicalCandidate.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: parent.path,
            isDirectory: &parentIsDirectory
        ), parentIsDirectory.boolValue else {
            return nil
        }

        // A final-path symlink is unnecessary for isolated UI QA and can be
        // dangling, in which case fileExists returns false and Foundation does
        // not resolve its destination. Reject every final symlink fail-closed.
        guard (try? fileManager.destinationOfSymbolicLink(
            atPath: lexicalCandidate.path
        )) == nil else {
            return nil
        }

        // Resolve the existing parent rather than the possibly non-existent
        // final file. Foundation otherwise leaves an intermediate symlink
        // unresolved and makes the lexical prefix check bypassable.
        let resolvedParent = parent
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let candidate: URL
        if fileManager.fileExists(atPath: lexicalCandidate.path) {
            candidate = lexicalCandidate
                .resolvingSymlinksInPath()
                .standardizedFileURL
        } else {
            candidate = resolvedParent.appendingPathComponent(
                lexicalCandidate.lastPathComponent,
                isDirectory: false
            )
        }
        let allowedRoots = [
            temporaryDirectory
                .resolvingSymlinksInPath()
                .standardizedFileURL,
            URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL,
        ]
        guard allowedRoots.contains(where: { root in
            candidate.path.hasPrefix(root.path + "/")
        }) else {
            return nil
        }
        return candidate
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
