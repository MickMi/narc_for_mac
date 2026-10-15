import Foundation
import Combine
import SQLite3

struct CodexCompletionEvent: Codable, Equatable {
    let schemaVersion: Int
    let threadID: String
    let turnID: String
    let state: String
    var title: String
    let timestamp: TimeInterval
    let isPreview: Bool
    var startedAt: TimeInterval? = nil
    var roundSummary: String? = nil
    var nextStep: String? = nil
    var blocker: String? = nil

    var identity: String { threadID + ":" + turnID + (isPreview ? ":preview" : "") }
    var hasRoundDetails: Bool { roundSummary != nil || nextStep != nil || blocker != nil }
    func canExpand(eventCount: Int) -> Bool { eventCount > 1 && hasRoundDetails }
    var threadURL: URL? {
        guard UUID(uuidString: threadID) != nil else { return nil }
        return URL(string: "codex://threads/\(threadID)")
    }

    func isValid(now: Date) -> Bool {
        let roundFields = [roundSummary, nextStep, blocker].compactMap { $0 }
        return schemaVersion == 1 && UUID(uuidString: threadID) != nil
            && UUID(uuidString: turnID) != nil
            && ["replyReady", "running", "interrupted"].contains(state)
            && !title.isEmpty && title.count <= 100
            && roundFields.allSatisfy {
                !$0.isEmpty && $0.count <= 160 && $0.rangeOfCharacter(from: .newlines) == nil
            }
            && timestamp.isFinite && timestamp <= now.timeIntervalSince1970 + 30
            && (startedAt == nil || (startedAt!.isFinite && startedAt! <= timestamp))
            && now.timeIntervalSince1970 - timestamp < 3600
    }

    static func decode(_ data: Data, now: Date = Date()) -> Self? {
        guard data.count <= 8192,
              let event = try? JSONDecoder().decode(Self.self, from: data),
              event.isValid(now: now) else { return nil }
        return event
    }
}

struct CodexCompletionState {
    private(set) var latestByThread: [String: CodexCompletionEvent] = [:]
    private var ready: [String: CodexCompletionEvent] = [:]
    var pendingEvents: [CodexCompletionEvent] {
        ready.values.sorted { $0.timestamp == $1.timestamp ? $0.identity < $1.identity : $0.timestamp > $1.timestamp }
    }
    var pending: CodexCompletionEvent? { pendingEvents.first }
    private(set) var acknowledged: [String]

    init(acknowledged: [String] = []) { self.acknowledged = Array(acknowledged.suffix(1024)) }

    mutating func receive(_ event: CodexCompletionEvent?, now: Date = Date()) {
        ready = ready.filter { $0.value.isValid(now: now) }
        latestByThread = latestByThread.filter { $0.value.isValid(now: now) }
        guard let event, event.isValid(now: now) else { return }
        if let old = latestByThread[event.threadID] {
            if old.identity == event.identity {
                guard event.timestamp >= old.timestamp, old.state != "interrupted" else { return }
            } else {
                guard (event.startedAt ?? event.timestamp) >= (old.startedAt ?? old.timestamp) else { return }
                acknowledge(identity: old.identity)
            }
        }
        latestByThread[event.threadID] = event
        if event.state != "replyReady" {
            if let old = ready[event.threadID] { acknowledge(identity: old.identity) }
            if event.state == "interrupted" { acknowledge(identity: event.identity) }
            return
        }
        guard !acknowledged.contains(event.identity) else { return }
        ready[event.threadID] = event
    }

    mutating func acknowledgePending() {
        guard let pending else { return }
        acknowledge(identity: pending.identity)
    }

    mutating func acknowledge(identity: String) {
        if !acknowledged.contains(identity) { acknowledged = Array((acknowledged + [identity]).suffix(1024)) }
        ready = ready.filter { $0.value.identity != identity }
    }
}

struct CodexConversation: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var lastSeen: TimeInterval
}

struct CodexReminderPreferences: Codable, Equatable {
    var enabled = false
    var enabledAfter: TimeInterval = 0
    var muted: Set<String> = []
    var excludedBefore: [String: TimeInterval] = [:]
    var names: [String: String] = [:]
    var conversations: [CodexConversation] = []

    func allows(_ event: CodexCompletionEvent) -> Bool {
        enabled && !muted.contains(event.threadID) && event.timestamp > enabledAfter
            && event.timestamp > (excludedBefore[event.threadID] ?? 0)
    }
}

@MainActor
final class CodexCompletionService: ObservableObject {
    @Published private(set) var pendingEvents: [CodexCompletionEvent] = []
    @Published private(set) var preferences: CodexReminderPreferences
    @Published private(set) var lastReceivedAt: Date?
    @Published private(set) var setupMessage: String?
    @Published private(set) var installing = false
    @Published private(set) var checkingConnection = false
    @Published private(set) var connectionInfo: CodexConnectionInfo?
    var pending: CodexCompletionEvent? { pendingEvents.first }
    private var state: CodexCompletionState
    private let defaults: UserDefaults
    private let key = "codexCompletionAcknowledgedV1"
    private let preferencesKey = "codexReminderPreferencesV2"
    private let eventFolder: URL
    private let codexFolder: URL
    private var verifiedThreadIDs: Set<String> = []
    private var timer: Timer?
    private var reading = false
    private let queue = DispatchQueue(label: "com.narc.codex-completion", qos: .utility)
    var onRefresh: (() -> Void)?

    init(defaults: UserDefaults = .standard, eventFolder: URL? = nil, codexFolder: URL? = nil) {
        self.defaults = defaults
        self.eventFolder = eventFolder ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NARC/codex-completion")
        self.codexFolder = codexFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        state = CodexCompletionState(acknowledged: defaults.stringArray(forKey: key) ?? [])
        if let data = defaults.data(forKey: preferencesKey),
           let saved = try? JSONDecoder().decode(CodexReminderPreferences.self, from: data) {
            preferences = saved
        } else {
            // Preserve an existing explicitly opted-in preview; new installations are off.
            preferences = CodexReminderPreferences(enabled: defaults.object(forKey: key) != nil)
        }
        // Persist migration before polling writes an empty acknowledgement ledger.
        // Otherwise a fresh disabled install could become enabled on its next launch.
        savePreferences()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    func stop() { timer?.invalidate(); timer = nil }

    func acknowledge(identity: String) {
        state.acknowledge(identity: identity)
        publish()
    }

    func resolveForOpening(_ event: CodexCompletionEvent, completion: @escaping (CodexCompletionEvent?) -> Void) {
        let folder = codexFolder
        queue.async { [weak self] in
            let metadata = CodexThreadMetadata.read(folder: folder, threadIDs: [event.threadID])
            DispatchQueue.main.async { [weak self] in
                guard let self, metadata[event.threadID]?.isInternal == false,
                      let current = self.pendingEvents.first(where: { $0.identity == event.identity }) else {
                    completion(nil)
                    return
                }
                // The stable ID selects the conversation, never a fuzzy title match.
                completion(current)
            }
        }
    }

    func setEnabled(_ enabled: Bool, now: Date = Date()) {
        preferences.enabled = enabled
        preferences.enabledAfter = now.timeIntervalSince1970
        for event in state.pendingEvents { state.acknowledge(identity: event.identity) }
        savePreferences()
        publish()
    }

    func setMuted(_ muted: Bool, threadID: String, now: Date = Date()) {
        if muted { preferences.muted.insert(threadID) } else { preferences.muted.remove(threadID) }
        preferences.excludedBefore[threadID] = now.timeIntervalSince1970
        for event in state.pendingEvents where event.threadID == threadID { state.acknowledge(identity: event.identity) }
        savePreferences()
        publish()
    }

    func setName(_ name: String, threadID: String) {
        // Preserve a trailing space while typing a multiword alias.
        let name = String(name.prefix(100))
        preferences.names[threadID] = name.isEmpty ? nil : name
        savePreferences()
        onRefresh?()
    }

    func displayTitle(threadID: String, fallback: String) -> String {
        let name = preferences.names[threadID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? (preferences.conversations.first { $0.id == threadID }?.title ?? fallback) : name
    }

    var conversations: [CodexConversation] {
        // Muted rules remain manageable even after their metadata leaves the recent list.
        let missing = preferences.muted.subtracting(preferences.conversations.map(\.id))
        return (preferences.conversations + missing.map {
            CodexConversation(id: $0, title: "对话 " + $0.suffix(8), lastSeen: 0)
        }).sorted { $0.lastSeen > $1.lastSeen }
    }

    func connectNotifications() {
        guard !installing, !checkingConnection else { return }
        installing = true
        setupMessage = nil
        CodexHookInstaller.run(install: true) { [weak self] result in
            guard let self else { return }
            self.installing = false
            switch result {
            case .success(let info):
                self.connectionInfo = info
                if info.status == .waiting || info.status == .connected { self.setEnabled(true) }
                self.setupMessage = info.message
            case .failure(let error):
                self.connectionInfo = .init(status: .error, receivedAt: nil, message: nil)
                self.setupMessage = error.localizedDescription
            }
        }
    }

    func checkConnection() {
        guard !installing, !checkingConnection else { return }
        checkingConnection = true
        CodexHookInstaller.run(install: false) { [weak self] result in
            guard let self else { return }
            self.checkingConnection = false
            switch result {
            case .success(let info):
                self.connectionInfo = info
                self.setupMessage = info.message
            case .failure(let error):
                self.connectionInfo = .init(status: .error, receivedAt: nil, message: nil)
                self.setupMessage = error.localizedDescription
            }
        }
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: preferencesKey) }
    }

    private func publish() {
        for event in state.pendingEvents where !preferences.allows(event) { state.acknowledge(identity: event.identity) }
        let next = state.pendingEvents.filter {
            preferences.allows($0) && ($0.isPreview || verifiedThreadIDs.contains($0.threadID))
        }
        if pendingEvents != next { pendingEvents = next }
        if defaults.stringArray(forKey: key) != state.acknowledged { defaults.set(state.acknowledged, forKey: key) }
        onRefresh?()
    }

    func ingest(_ events: [CodexCompletionEvent], now: Date = Date(),
                metadata: [String: CodexThreadMetadata] = [:]) {
        state.receive(nil, now: now)
        verifiedThreadIDs = Set(metadata.keys.filter { metadata[$0]?.isInternal == false })
        let oldPreferences = preferences
        for id in metadata.keys where metadata[id]?.isInternal == true {
            for event in state.pendingEvents where event.threadID == id { state.acknowledge(identity: event.identity) }
            preferences.conversations.removeAll { $0.id == id }
        }
        for event in events.sorted(by: {
            let a = $0.startedAt ?? $0.timestamp, b = $1.startedAt ?? $1.timestamp
            return a == b ? $0.timestamp < $1.timestamp : a < b
        }) where event.isValid(now: now) {
            guard event.isPreview || metadata[event.threadID]?.isInternal == false else { continue }
            var event = event
            if !event.isPreview, let title = metadata[event.threadID]?.title { event.title = title }
            if event.title == "对话 " + event.threadID.suffix(8),
               let known = preferences.conversations.first(where: { $0.id == event.threadID })?.title {
                event.title = known // A transient metadata failure must not erase a resolved title.
            }
            state.receive(event, now: now)
            if !event.isPreview {
                let received = Date(timeIntervalSince1970: event.timestamp)
                if lastReceivedAt == nil || received > lastReceivedAt! { lastReceivedAt = received }
                if let i = preferences.conversations.firstIndex(where: { $0.id == event.threadID }) {
                    if event.timestamp >= preferences.conversations[i].lastSeen {
                        preferences.conversations[i] = .init(id: event.threadID, title: event.title, lastSeen: event.timestamp)
                    }
                } else {
                    preferences.conversations.append(.init(id: event.threadID, title: event.title, lastSeen: event.timestamp))
                }
            }
        }
        preferences.conversations = Array(preferences.conversations.sorted { $0.lastSeen > $1.lastSeen }.prefix(200))
        if oldPreferences != preferences { savePreferences() }
        publish()
    }

    private func refresh() {
        guard !reading else { return }
        reading = true
        let folder = eventFolder
        let codexFolder = codexFolder
        queue.async { [weak self] in
            let events = Self.readEvents(folder)
            let metadata = CodexThreadMetadata.read(folder: codexFolder, threadIDs: Set(events.map(\.threadID)))
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reading = false
                self.ingest(events, metadata: metadata)
            }
        }
    }

    nonisolated static func readEvents(_ folder: URL) -> [CodexCompletionEvent] {
        var events = [CodexCompletionEvent]()
        if let legacy = read(folder.appendingPathComponent("latest.json")) { events.append(legacy) }
        let directory = folder.appendingPathComponent("events")
        guard safePath(directory), let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return events }
        let recent = files.filter { $0.pathExtension == "json" }.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.prefix(512)
        // New protocol wins over a simultaneously installed legacy adapter for the same turn.
        let multi = recent.compactMap { read($0) }
        let ids = Set(multi.map(\.identity))
        return events.filter { !ids.contains($0.identity) } + multi
    }

    nonisolated static func safePath(_ url: URL) -> Bool {
        var path = url
        while path.path != "/" {
            if (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return false }
            path.deleteLastPathComponent()
        }
        return true
    }

    nonisolated private static func read(_ url: URL) -> CodexCompletionEvent? {
        let fm = FileManager.default
        guard safePath(url), let attributes = try? fm.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let size = attributes[.size] as? NSNumber, size.intValue <= 8192,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8193) else { return nil }
        return CodexCompletionEvent.decode(data)
    }
}

/// Read only bounded titles and source kinds; never query a transcript or prompt.
struct CodexThreadMetadata {
    var title: String?
    var isInternal: Bool

    static func read(folder: URL, threadIDs: Set<String>) -> [String: Self] {
        guard !threadIDs.isEmpty, CodexCompletionService.safePath(folder),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return [:] }
        let databases = files.filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
            .sorted { (Int($0.deletingPathExtension().lastPathComponent.dropFirst(6)) ?? -1) > (Int($1.deletingPathExtension().lastPathComponent.dropFirst(6)) ?? -1) }
        guard let url = databases.first, CodexCompletionService.safePath(url),
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return [:] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return [:]
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        var statement: OpaquePointer?
        // Older clients do not have `name`; title/source remain a safe fallback.
        let queries = ["SELECT substr(COALESCE(NULLIF(name,''),title),1,100), source FROM threads WHERE id = ?",
                       "SELECT substr(title,1,100), source FROM threads WHERE id = ?"]
        for query in queries {
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK { break }
        }
        guard let statement else { return [:] }
        defer { sqlite3_finalize(statement) }
        var result: [String: Self] = [:]
        for id in threadIDs.prefix(512) where UUID(uuidString: id) != nil {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            let status = id.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard status == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW,
                  let rawSource = sqlite3_column_text(statement, 1) else { continue }
            let source = String(cString: rawSource)
            let object = source.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let title = sqlite3_column_text(statement, 0).map { String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            result[id] = .init(title: title?.isEmpty == false ? title : nil,
                              isInternal: source == "subagent" || object?["subagent"] != nil)
        }
        return result
    }
}
