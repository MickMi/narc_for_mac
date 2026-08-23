import Foundation

/// Stable locations where a built-in module can be surfaced by the host app.
enum NARCModulePlacement: String, Codable, CaseIterable, Hashable {
    case panel
    case assistantHub
    case standaloneWindow
}

/// Capabilities are declarations for host UI and orchestration, not executable plugins.
enum NARCModuleCapability: String, Codable, CaseIterable, Hashable {
    case quickCapture
    case browse
    case search
    case status
    case workspace
}

/// Compile-time metadata for a built-in NARC feature module.
struct NARCModule: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let systemImageName: String
    let placements: Set<NARCModulePlacement>
    let capabilities: Set<NARCModuleCapability>
    let sortOrder: Int

    init(
        id: String,
        displayName: String,
        systemImageName: String,
        placements: Set<NARCModulePlacement>,
        capabilities: Set<NARCModuleCapability>,
        sortOrder: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.systemImageName = systemImageName
        self.placements = placements
        self.capabilities = capabilities
        self.sortOrder = sortOrder
    }
}
