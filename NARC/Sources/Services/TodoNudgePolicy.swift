import Foundation
import Combine

struct TodoReminderConfiguration: Codable, Equatable {
    var isEnabled = true
    var minutes = [11 * 60, 14 * 60 + 30]
    var effectiveFrom = Date.distantPast
}

/// Separate from Todo content; nil defaults keeps isolated development runs
/// from changing the user's reminder preferences.
@MainActor
final class TodoReminderSettings: ObservableObject {
    static let storageKey = "todoReview.configuration.v1"
    @Published private(set) var configuration: TodoReminderConfiguration
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.storageKey) {
            if let value = try? JSONDecoder().decode(TodoReminderConfiguration.self, from: data),
               value.minutes.allSatisfy({ (0..<1440).contains($0) }),
               Set(value.minutes).count == value.minutes.count {
                configuration = value
                configuration.minutes.sort()
            } else {
                // Invalid settings must not silently turn reminders on.
                configuration = TodoReminderConfiguration(isEnabled: false)
            }
        } else {
            configuration = TodoReminderConfiguration()
        }
    }

    @discardableResult
    func update(isEnabled: Bool? = nil, minutes: [Int]? = nil, now: Date = Date()) -> Bool {
        var next = configuration
        if let minutes {
            guard minutes.allSatisfy({ (0..<1440).contains($0) }),
                  Set(minutes).count == minutes.count else { return false }
            next.minutes = minutes.sorted()
        }
        if let isEnabled { next.isEnabled = isEnabled }
        next.effectiveFrom = now
        guard let data = try? JSONEncoder().encode(next) else { return false }
        defaults?.set(data, forKey: Self.storageKey)
        configuration = next
        return true
    }
}

struct TodoNudgeLedgerState: Codable, Equatable {
    var consumedThrough: Date?
    var snoozedUntil: Date?
    static let empty = TodoNudgeLedgerState()
}

enum TodoNudgeDecision: Equatable {
    case present
    case wait(until: Date)
    case suppress
}

enum TodoNudgeLedgerStorage: Equatable {
    case persistent
    case transient

    static func resolve(
        assistantStorageSelection: AssistantStorageSelection
    ) -> TodoNudgeLedgerStorage {
        switch assistantStorageSelection {
        case .standard:
            return .persistent
        case .temporary, .invalidOverride:
            return .transient
        }
    }
}

/// Calendar-based, content-free schedule. Only the latest recent occurrence is
/// eligible, so waking or restarting cannot replay a backlog of reminders.
enum TodoNudgePolicy {
    static let startupWarmup: TimeInterval = 30
    static let todoChangeSilence: TimeInterval = 15
    static let catchUpWindow: TimeInterval = 10 * 60
    static let snoozeDuration: TimeInterval = 60 * 60
    static let visibleDuration: TimeInterval = 30
    static let errorVisibleDuration: TimeInterval = 30

    static func dueOccurrence(
        now: Date,
        configuration: TodoReminderConfiguration,
        ledger: TodoNudgeLedgerState,
        calendar: Calendar = .current
    ) -> Date? {
        guard configuration.isEnabled else { return nil }
        // A user-requested snooze also suppresses intervening scheduled slots.
        if let snooze = ledger.snoozedUntil, snooze > now { return nil }
        let today = calendar.startOfDay(for: now)
        let days = [today, calendar.date(byAdding: .day, value: -1, to: today)!]
        var occurrences = days.flatMap { day in
            configuration.minutes.compactMap { minute -> Date? in
                guard (0..<1440).contains(minute),
                      let date = calendar.date(
                        bySettingHour: minute / 60, minute: minute % 60, second: 0,
                        of: day, matchingPolicy: .strict, repeatedTimePolicy: .first
                      ), calendar.isDate(date, inSameDayAs: day) else { return nil }
                return date
            }
        }
        if let snooze = ledger.snoozedUntil { occurrences.append(snooze) }
        return occurrences.filter {
            $0 <= now && now.timeIntervalSince($0) <= catchUpWindow
                && $0 > (ledger.consumedThrough ?? .distantPast)
                && $0 >= configuration.effectiveFrom
        }.max()
    }

    static func evaluate(
        now: Date,
        earliestPresentationAt: Date,
        hasAvailableTodo: Bool,
        isPresentationBlocked: Bool,
        ledger: TodoNudgeLedgerState,
        configuration: TodoReminderConfiguration = TodoReminderConfiguration(),
        calendar: Calendar = .current
    ) -> TodoNudgeDecision {
        guard hasAvailableTodo, !isPresentationBlocked,
              dueOccurrence(now: now, configuration: configuration, ledger: ledger, calendar: calendar) != nil else {
            return .suppress
        }
        guard now >= earliestPresentationAt else {
            return .wait(until: earliestPresentationAt)
        }
        return .present
    }

    static func recordingPresentation(
        at now: Date,
        ledger: TodoNudgeLedgerState
    ) -> TodoNudgeLedgerState {
        TodoNudgeLedgerState(consumedThrough: max(now, ledger.consumedThrough ?? .distantPast))
    }
}

enum TodoNudgeLedgerDefaults {
    private static let storageKey = "todoReview.ledger.v1"

    static func load(from defaults: UserDefaults = .standard) -> TodoNudgeLedgerState {
        guard let data = defaults.data(forKey: storageKey) else { return .empty }
        return (try? JSONDecoder().decode(TodoNudgeLedgerState.self, from: data)) ?? .empty
    }

    static func save(
        _ ledger: TodoNudgeLedgerState,
        to defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct TodoReviewSummary {
    let featured: TodoItem?
    let others: [TodoItem]
    let remainingCount: Int
    let deferredCount: Int

    init(availableTodos: [TodoItem], incompleteCount: Int) {
        featured = availableTodos.first
        others = Array(availableTodos.dropFirst().prefix(3))
        remainingCount = max(0, incompleteCount - (featured == nil ? 0 : 1))
        deferredCount = max(0, incompleteCount - availableTodos.count)
    }
}
