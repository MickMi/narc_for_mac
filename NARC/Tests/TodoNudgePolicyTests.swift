import Foundation
import SwiftUI
import Testing
@testable import NARC

private let reviewCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func reviewDate(_ hour: Int, _ minute: Int = 0, day: Int = 17) -> Date {
    reviewCalendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

private func decision(
    at now: Date, ledger: TodoNudgeLedgerState = .empty,
    configuration: TodoReminderConfiguration = TodoReminderConfiguration(),
    hasTodo: Bool = true, blocked: Bool = false, earliest: Date = .distantPast
) -> TodoNudgeDecision {
    TodoNudgePolicy.evaluate(now: now, earliestPresentationAt: earliest,
                            hasAvailableTodo: hasTodo, isPresentationBlocked: blocked,
                            ledger: ledger, configuration: configuration, calendar: reviewCalendar)
}

@Test
func todoNudgeUsesOnlyConfiguredDailyTimes() {
    #expect(decision(at: reviewDate(10, 59)) == .suppress)
    #expect(decision(at: reviewDate(11)) == .present)
    #expect(decision(at: reviewDate(12)) == .suppress)
    #expect(decision(at: reviewDate(14, 30)) == .present)
    #expect(decision(at: reviewDate(15)) == .suppress)
    #expect(decision(at: reviewDate(11), configuration: .init(minutes: [12 * 60])) == .suppress)
}

@Test
func todoNudgeRequiresEnabledCandidateAndUnblockedSurface() {
    let now = reviewDate(11)
    #expect(decision(at: now, hasTodo: false) == .suppress)
    #expect(decision(at: now, blocked: true) == .suppress)
    #expect(decision(at: now, configuration: .init(isEnabled: false)) == .suppress)
    #expect(decision(at: now, configuration: .init(minutes: [])) == .suppress)
    #expect(decision(at: now, earliest: now.addingTimeInterval(30)) == .wait(until: now.addingTimeInterval(30)))
}

@Test
func todoNudgeRecordsConsumptionAndAllowsNextSlotAndNextDay() {
    let now = reviewDate(11)
    let ledger = TodoNudgePolicy.recordingPresentation(at: now, ledger: .empty)
    #expect(decision(at: now.addingTimeInterval(30), ledger: ledger) == .suppress)
    let hourly = TodoReminderConfiguration(minutes: [660, 690, 720, 750])
    #expect(decision(at: reviewDate(11, 30), ledger: ledger, configuration: hourly) == .present)
    #expect(decision(at: reviewDate(11, day: 18), ledger: ledger) == .present)
}

@Test
func todoNudgeWakeCatchesOnlyLatestRecentSlotAndNeverReplaysBacklog() {
    let now = reviewDate(11, 7)
    let config = TodoReminderConfiguration(minutes: [660, 662, 665])
    #expect(TodoNudgePolicy.dueOccurrence(now: now, configuration: config, ledger: .empty,
                                        calendar: reviewCalendar) == reviewDate(11, 5))
    let consumed = TodoNudgePolicy.recordingPresentation(at: now, ledger: .empty)
    #expect(decision(at: now.addingTimeInterval(5), ledger: consumed, configuration: config) == .suppress)
    #expect(decision(at: reviewDate(11, 11)) == .suppress)
    #expect(decision(at: reviewDate(11, 10)) == .present)
}

@Test
func todoNudgeEmptySlotCanBeConsumedAndClockRollbackCannotReplay() {
    let now = reviewDate(11, 3)
    let ledger = TodoNudgePolicy.recordingPresentation(at: now, ledger: .empty)
    #expect(decision(at: reviewDate(11, 4), ledger: ledger) == .suppress)
    #expect(decision(at: reviewDate(11, 1), ledger: ledger) == .suppress)
    let rolledBack = TodoNudgePolicy.recordingPresentation(at: reviewDate(10), ledger: ledger)
    #expect(rolledBack.consumedThrough == now)
}

@Test
func todoNudgeCatchUpCrossesMidnightWithoutDailyCounter() {
    let config = TodoReminderConfiguration(minutes: [23 * 60 + 58])
    #expect(decision(at: reviewDate(0, 3, day: 18), configuration: config) == .present)
    #expect(decision(at: reviewDate(0, 9, day: 18), configuration: config) == .suppress)
}

@Test
func todoNudgeSnoozeSuppressesInterveningSlotsThenExpiresOnce() {
    let ledger = TodoNudgeLedgerState(consumedThrough: reviewDate(11), snoozedUntil: reviewDate(12))
    let config = TodoReminderConfiguration(minutes: [660, 690])
    #expect(decision(at: reviewDate(11, 30), ledger: ledger, configuration: config) == .suppress)
    #expect(decision(at: reviewDate(12), ledger: ledger, configuration: config) == .present)
    let consumed = TodoNudgePolicy.recordingPresentation(at: reviewDate(12), ledger: ledger)
    #expect(consumed.snoozedUntil == nil)
    #expect(decision(at: reviewDate(12, 1), ledger: consumed, configuration: config) == .suppress)
    #expect(decision(at: reviewDate(12, 11), ledger: ledger, configuration: config) == .suppress)
}

@Test
func todoNudgeScheduleEditsDoNotBackfillPastSlots() {
    let config = TodoReminderConfiguration(effectiveFrom: reviewDate(11, 2))
    #expect(decision(at: reviewDate(11, 3), configuration: config) == .suppress)
    #expect(decision(at: reviewDate(14, 30), configuration: config) == .present)
}

@Test
func todoNudgeDSTSkipsMissingTimeAndDoesNotRepeatFoldedTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 2))!
    #expect(TodoNudgePolicy.dueOccurrence(now: spring, configuration: .init(minutes: [150]),
                                        ledger: .empty, calendar: calendar) == nil)
    let autumn = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
    let first = calendar.date(bySettingHour: 1, minute: 30, second: 0, of: autumn,
                              matchingPolicy: .strict, repeatedTimePolicy: .first)!
    #expect(TodoNudgePolicy.dueOccurrence(now: first, configuration: .init(minutes: [90]),
                                        ledger: .empty, calendar: calendar) == first)
    #expect(TodoNudgePolicy.dueOccurrence(now: first.addingTimeInterval(3600), configuration: .init(minutes: [90]),
                                        ledger: .empty, calendar: calendar) == nil)
}

@Test
func isolatedAssistantRunsKeepTheNudgeLedgerTransient() {
    #expect(TodoNudgeLedgerStorage.resolve(assistantStorageSelection: .standard) == .persistent)
    #expect(TodoNudgeLedgerStorage.resolve(assistantStorageSelection: .temporary(URL(fileURLWithPath: "/private/tmp/review.json"))) == .transient)
    #expect(TodoNudgeLedgerStorage.resolve(assistantStorageSelection: .invalidOverride) == .transient)
}

@Test
@MainActor
func todoReminderSettingsRoundTripValidateAndKeepContentOut() throws {
    let suite = "TodoReview-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = TodoReminderSettings(defaults: defaults)
    #expect(settings.configuration.minutes == [660, 870])
    #expect(settings.update(minutes: [870, 660, 1080], now: reviewDate(9)))
    #expect(settings.configuration.minutes == [660, 870, 1080])
    #expect(!settings.update(minutes: [660, 660]))
    #expect(!settings.update(minutes: [-1]))
    #expect(!settings.update(minutes: [1440]))
    #expect(settings.update(isEnabled: false, now: reviewDate(10)))
    let reloaded = TodoReminderSettings(defaults: defaults)
    #expect(reloaded.configuration == settings.configuration)
    #expect(settings.update(minutes: []))
    #expect(settings.configuration.minutes.isEmpty)
    let data = try #require(defaults.data(forKey: TodoReminderSettings.storageKey))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["isEnabled", "minutes", "effectiveFrom"])
}

@Test
@MainActor
func todoReminderMalformedSettingsFailClosedAndTransientSettingsStayIsolated() throws {
    let suite = "TodoReview-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Data("broken".utf8), forKey: TodoReminderSettings.storageKey)
    #expect(!TodoReminderSettings(defaults: defaults).configuration.isEnabled)
    let transient = TodoReminderSettings(defaults: nil)
    #expect(transient.update(minutes: [600]))
    #expect(defaults.data(forKey: TodoReminderSettings.storageKey) == Data("broken".utf8))
}

@Test
func todoNudgeLedgerRoundTripsAndIgnoresOldIntervalState() throws {
    let suite = "TodoReviewLedger-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(99, forKey: "todoNudge.shownCount")
    defaults.set(Date.distantFuture, forKey: "todoNudge.nextAllowedAt")
    #expect(TodoNudgeLedgerDefaults.load(from: defaults) == .empty)
    let state = TodoNudgeLedgerState(consumedThrough: reviewDate(11), snoozedUntil: reviewDate(12))
    TodoNudgeLedgerDefaults.save(state, to: defaults)
    #expect(TodoNudgeLedgerDefaults.load(from: defaults) == state)
}

@Test
func todoReviewSummaryFeaturesOneTaskAndBoundsTheRemainingPreview() {
    let items = (0..<6).map { TodoItem(title: "Task \($0)") }
    let review = TodoReviewSummary(availableTodos: items, incompleteCount: 8)
    #expect(review.featured?.id == items[0].id)
    #expect(review.others.map(\.id) == Array(items[1...3]).map(\.id))
    #expect(review.remainingCount == 7)
    #expect(review.deferredCount == 2)
    let empty = TodoReviewSummary(availableTodos: [], incompleteCount: 0)
    #expect(empty.featured == nil)
    #expect(empty.others.isEmpty)
    #expect(empty.remainingCount == 0)
}

@Test
@MainActor
func todoNudgePanelCannotTakeKeyboardFocus() {
    let panel = TodoNudgeWindow(rootView: Text("Isolated review test"))
    #expect(!panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(!panel.isVisible)
}

@Test
func todoNudgePreviewClosesTheMainPanelBeforePresenting() throws {
    // Structural regression guard; real click and focus checks remain manual.
    let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/App/AppDelegate.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let start = try #require(source.range(of: "onPreviewReminder: {"))
    let suffix = String(source[start.upperBound...])
    let close = try #require(suffix.range(of: "self.hidePanel()"))
    let show = try #require(suffix.range(of: "self.presentTodoNudge("))
    #expect(close.lowerBound < show.lowerBound)
    #expect(source.contains("if !todoNudgeIsPreview { dismissTodoNudge() }"))
}
