import Testing
import Cocoa
@testable import NARC

// MARK: - WindowLayoutState Tests

@Test func confirmedWindowPlacementRemainsCrossableWithoutFiveSecondExpiry() {
    let state = WindowLayoutState()
    let windowID: CGWindowID = 99_999
    let processID: pid_t = 321
    let displayID: CGDirectDisplayID = 7
    let screenBounds = CGRect(x: 0, y: 24, width: 1_920, height: 1_056)
    let frame = WindowMoveFrame(
        position: CGPoint(x: 960, y: 24),
        size: CGSize(width: 960, height: 1_056)
    )
    let start = Date(timeIntervalSince1970: 1_000)

    #expect(!state.shouldCrossScreen(
        windowID: windowID,
        processID: processID,
        layout: .rightHalf,
        screenDisplayID: displayID,
        screenBounds: screenBounds,
        currentFrame: frame,
        now: start
    ))

    state.recordPending(
        windowID: windowID,
        processID: processID,
        layout: .rightHalf,
        appliedLayout: .rightHalf,
        screenDisplayID: displayID,
        screenBounds: screenBounds,
        requestedFrame: frame,
        generation: 1,
        now: start
    )
    #expect(state.confirm(
        windowID: windowID,
        processID: processID,
        layout: .rightHalf,
        appliedLayout: .rightHalf,
        screenDisplayID: displayID,
        screenBounds: screenBounds,
        acceptedFrame: frame,
        generation: 1,
        now: start.addingTimeInterval(0.02)
    ))

    #expect(state.shouldCrossScreen(
        windowID: windowID,
        processID: processID,
        layout: .rightHalf,
        screenDisplayID: displayID,
        screenBounds: screenBounds,
        currentFrame: frame,
        now: start.addingTimeInterval(60)
    ))
}

@Test func manualWindowMoveInvalidatesConfirmedCrossScreenIntent() {
    let state = WindowLayoutState()
    let frame = WindowMoveFrame(
        position: CGPoint(x: 0, y: 24),
        size: CGSize(width: 960, height: 1_056)
    )
    let screenBounds = CGRect(x: 0, y: 24, width: 1_920, height: 1_056)
    state.confirm(
        windowID: 99_998,
        processID: 654,
        layout: .leftHalf,
        appliedLayout: .leftHalf,
        screenDisplayID: 8,
        screenBounds: screenBounds,
        acceptedFrame: frame,
        generation: 3
    )

    let manuallyMoved = WindowMoveFrame(
        position: CGPoint(x: 140, y: 90),
        size: frame.size
    )
    #expect(!state.shouldCrossScreen(
        windowID: 99_998,
        processID: 654,
        layout: .leftHalf,
        screenDisplayID: 8,
        screenBounds: screenBounds,
        currentFrame: manuallyMoved
    ))
    #expect(!state.shouldCrossScreen(
        windowID: 99_998,
        processID: 654,
        layout: .leftHalf,
        screenDisplayID: 8,
        screenBounds: screenBounds,
        currentFrame: frame
    ))
}

// MARK: - ScreenNavigator Tests

@Test func crossScreenEntryLayoutFlipsDirection() async throws {
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .leftHalf) == .rightHalf)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .rightHalf) == .leftHalf)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .topHalf) == .bottomHalf)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .bottomHalf) == .topHalf)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .topLeft) == .topRight)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .topRight) == .topLeft)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .bottomLeft) == .bottomRight)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .bottomRight) == .bottomLeft)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .center) == .center)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .fullScreen) == .fullScreen)
}

@Test func fullScreenAndCenterHaveNoCrossScreenEdges() async throws {
    #expect(ScreenNavigator.crossScreenEdges(for: .fullScreen).isEmpty)
    #expect(ScreenNavigator.crossScreenEdges(for: .center).isEmpty)
}

@Test func directionalLayoutsHaveCorrectEdges() async throws {
    #expect(ScreenNavigator.crossScreenEdges(for: .leftHalf) == [.left])
    #expect(ScreenNavigator.crossScreenEdges(for: .rightHalf) == [.right])
    #expect(ScreenNavigator.crossScreenEdges(for: .topHalf) == [.top])
    #expect(ScreenNavigator.crossScreenEdges(for: .bottomHalf) == [.bottom])
}

@Test
func isolatedAssistantStorageAcceptsOnlyAbsoluteTemporaryPaths() {
    let systemTemporaryDirectory = FileManager.default.temporaryDirectory
        .resolvingSymlinksInPath()
        .standardizedFileURL
    let systemCandidate = systemTemporaryDirectory
        .appendingPathComponent("narc-isolated-assistant.json", isDirectory: false)
    let privateTmpCandidate = URL(
        fileURLWithPath: "/private/tmp/narc-isolated-assistant.json",
        isDirectory: false
    )
    let resolvedPrivateTmpCandidate = privateTmpCandidate
        .deletingLastPathComponent()
        .resolvingSymlinksInPath()
        .standardizedFileURL
        .appendingPathComponent(privateTmpCandidate.lastPathComponent, isDirectory: false)

    #expect(
        DevRuntimeOptions.validatedAssistantStorageURL(
            rawPath: privateTmpCandidate.path,
            temporaryDirectory: systemTemporaryDirectory
        )?.path == resolvedPrivateTmpCandidate.path
    )
    #expect(
        DevRuntimeOptions.validatedAssistantStorageURL(
            rawPath: systemCandidate.path,
            temporaryDirectory: systemTemporaryDirectory
        )?.path == systemCandidate.path
    )
    #expect(
        DevRuntimeOptions.validatedAssistantStorageURL(
            rawPath: "/Users/example/Library/Application Support/NARC/assistant-v1.json",
            temporaryDirectory: systemTemporaryDirectory
        ) == nil
    )
    #expect(
        DevRuntimeOptions.validatedAssistantStorageURL(
            rawPath: "relative/assistant.json",
            temporaryDirectory: systemTemporaryDirectory
        ) == nil
    )
}

@Test
func isolatedAssistantStorageRejectsASymlinkEscape() throws {
    let fileManager = FileManager.default
    let base = fileManager.temporaryDirectory
        .appendingPathComponent("narc-storage-path-tests-\(UUID().uuidString)", isDirectory: true)
    let allowed = base.appendingPathComponent("allowed", isDirectory: true)
    let outside = base.appendingPathComponent("outside", isDirectory: true)
    let link = allowed.appendingPathComponent("escape", isDirectory: true)
    defer { try? fileManager.removeItem(at: base) }

    try fileManager.createDirectory(at: allowed, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(at: link, withDestinationURL: outside)

    #expect(
        DevRuntimeOptions.validatedAssistantStorageURL(
            rawPath: link.appendingPathComponent("assistant.json").path,
            temporaryDirectory: allowed
        ) == nil
    )

    let outsideFile = outside.appendingPathComponent("personal.json", isDirectory: false)
    let fileLink = allowed.appendingPathComponent("assistant.json", isDirectory: false)
    #expect(fileManager.createFile(atPath: outsideFile.path, contents: Data()))
    try fileManager.createSymbolicLink(at: fileLink, withDestinationURL: outsideFile)

    #expect(
        DevRuntimeOptions.validatedAssistantStorageURL(
            rawPath: fileLink.path,
            temporaryDirectory: allowed
        ) == nil
    )

    let danglingFileLink = allowed.appendingPathComponent(
        "dangling-assistant.json",
        isDirectory: false
    )
    try fileManager.createSymbolicLink(
        at: danglingFileLink,
        withDestinationURL: outside.appendingPathComponent("missing.json")
    )

    #expect(
        DevRuntimeOptions.validatedAssistantStorageURL(
            rawPath: danglingFileLink.path,
            temporaryDirectory: allowed
        ) == nil
    )
}
