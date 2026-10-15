import Combine
import Foundation

enum InstantQuestionStoreFailure: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case loadFailed
    case saveFailed
    case writesBlockedAfterLoadFailure

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema:
            return "问答记录来自更高版本的 NARC，当前版本不会覆盖它。"
        case .loadFailed:
            return "无法读取已保存问答，原文件已保留。"
        case .saveFailed:
            return "问答保存失败，请检查磁盘空间和文件权限。"
        case .writesBlockedAfterLoadFailure:
            return "检测到无法读取的问答数据，为避免覆盖已停止写入。"
        }
    }
}

@MainActor
final class InstantQuestionStore: ObservableObject {
    @Published private(set) var records: [SavedInstantQuestion] = []
    @Published private(set) var lastError: InstantQuestionStoreFailure?

    let storageURL: URL

    private let fileManager: FileManager
    private var writesBlocked = false

    init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        load()
    }

    @discardableResult
    func save(_ record: SavedInstantQuestion) -> Bool {
        var next = records
        if let index = next.firstIndex(where: { $0.id == record.id }) {
            next[index] = record
        } else {
            next.append(record)
        }
        return persist(next)
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard records.contains(where: { $0.id == id }) else { return false }
        return persist(records.filter { $0.id != id })
    }

    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let snapshot = try Self.makeDecoder().decode(InstantQuestionSnapshot.self, from: data)
            guard snapshot.schemaVersion == InstantQuestionSnapshot.currentSchemaVersion else {
                writesBlocked = true
                lastError = .unsupportedSchema(snapshot.schemaVersion)
                return
            }
            records = Self.sorted(snapshot.records)
        } catch {
            writesBlocked = true
            lastError = .loadFailed
        }
    }

    private func persist(_ nextRecords: [SavedInstantQuestion]) -> Bool {
        guard !writesBlocked else {
            lastError = .writesBlockedAfterLoadFailure
            return false
        }
        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let snapshot = InstantQuestionSnapshot(records: Self.sorted(nextRecords))
            let data = try Self.makeEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
            records = snapshot.records
            lastError = nil
            return true
        } catch {
            lastError = .saveFailed
            return false
        }
    }

    private static func sorted(_ records: [SavedInstantQuestion]) -> [SavedInstantQuestion] {
        records.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("NARC", isDirectory: true)
            .appendingPathComponent("instant-questions-v1.json", isDirectory: false)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
