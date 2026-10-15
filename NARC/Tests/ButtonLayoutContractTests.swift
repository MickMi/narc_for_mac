import Foundation
import Testing

/// Source guards only: actual window sizes and pointer behavior need UI review.
@Suite(.serialized)
struct ButtonLayoutContractTests {
    private var project: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func check(_ target: URL) throws -> (Int32, String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-B",
            project.appendingPathComponent("scripts/tests/button-layout-contract.py").path, target.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @Test func currentSearchButtonsKeepSingleLineProtection() throws {
        let (status, output) = try check(project)
        #expect(status == 0, Comment(rawValue: output))
        #expect(output.contains("7/7"))
    }

    @Test func removedProtectionFailsWithoutEditingRealSources() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("narc-button-guard-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let views = temporary.appendingPathComponent("NARC/Sources/Views")
        try FileManager.default.createDirectory(at: views, withIntermediateDirectories: true)
        for name in ["InstantQuestionView.swift", "InstantQuestionSettingsView.swift"] {
            let source = try String(contentsOf: project.appendingPathComponent("NARC/Sources/Views/" + name), encoding: .utf8)
            try source.replacingOccurrences(of: ".lineLimit(1)", with: ".lineLimit(2)")
                .write(to: views.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let (status, output) = try check(temporary)
        #expect(status == 1, Comment(rawValue: output))
        #expect(output.contains("FAIL"))
    }

    @Test func missingSourcesAreNotReportedAsPassing() throws {
        let (status, _) = try check(project.appendingPathComponent("not-a-source-checkout-" + UUID().uuidString))
        #expect(status == 2)
    }
}
