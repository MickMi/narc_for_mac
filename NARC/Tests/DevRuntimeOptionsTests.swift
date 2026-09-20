import Foundation
import Testing
@testable import NARC

@Test
func debugAssistantStorageOverrideCanKeepRealAccessibilityEnabled() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("narc-dev-storage-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = directory.appendingPathComponent("selection-matrix.json")

    #expect(
        DevRuntimeOptions.resolvedAssistantStorageSelection(rawPath: file.path)
            == .temporary(file.standardizedFileURL)
    )
    #expect(DevRuntimeOptions.resolvedAssistantStorageSelection(rawPath: nil) == .standard)
}

@Test
func invalidDebugAssistantStorageOverrideNeverFallsBackToPersonalData() {
    #expect(
        DevRuntimeOptions.resolvedAssistantStorageSelection(
            rawPath: "/Users/example/Documents/not-temporary.json"
        ) == .invalidOverride
    )
}
