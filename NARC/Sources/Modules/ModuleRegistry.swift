import Foundation

enum ModuleRegistryError: Error, Equatable {
    case duplicateModuleID(String)
}

/// Ordered registry for compile-time built-in modules.
struct ModuleRegistry {
    let modules: [NARCModule]

    private let modulesByID: [String: NARCModule]

    init() {
        let modules = Self.sorted(Self.defaultModules)
        self.modules = modules
        self.modulesByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
    }

    init(modules: [NARCModule]) throws {
        var seenIDs = Set<String>()

        for module in modules where !seenIDs.insert(module.id).inserted {
            throw ModuleRegistryError.duplicateModuleID(module.id)
        }

        let modules = Self.sorted(modules)
        self.modules = modules
        self.modulesByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
    }

    func module(id: String) -> NARCModule? {
        modulesByID[id]
    }

    func modules(in placement: NARCModulePlacement) -> [NARCModule] {
        modules.filter { $0.placements.contains(placement) }
    }

    private static func sorted(_ modules: [NARCModule]) -> [NARCModule] {
        modules.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.id < $1.id
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    private static let defaultModules: [NARCModule] = [
        NARCModule(
            id: "assistant",
            displayName: "Assistant",
            systemImageName: "sparkles",
            placements: [.panel, .assistantHub, .standaloneWindow],
            capabilities: [.quickCapture, .browse, .search],
            sortOrder: 100
        ),
        NARCModule(
            id: "notifications",
            displayName: "Notifications",
            systemImageName: "bell",
            placements: [.panel],
            capabilities: [.browse, .status],
            sortOrder: 200
        ),
        NARCModule(
            id: "windows",
            displayName: "Windows",
            systemImageName: "macwindow.on.rectangle",
            placements: [.panel],
            capabilities: [.browse, .status],
            sortOrder: 300
        )
    ]
}
