import Testing
@testable import NARC

@Test
func moduleRegistryUsesStableDefaultOrder() {
    let registry = ModuleRegistry()

    #expect(registry.modules.map(\.id) == [
        "assistant",
        "notifications",
        "windows"
    ])
}

@Test
func moduleRegistryFindsModulesByIDAndPlacement() throws {
    let registry = ModuleRegistry()
    let assistant = try #require(registry.module(id: "assistant"))

    #expect(assistant.capabilities.contains(.quickCapture))
    #expect(registry.module(id: "missing") == nil)
    #expect(registry.module(id: "workspace") == nil)
    #expect(registry.modules(in: .standaloneWindow).map(\.id) == [
        "assistant"
    ])
}

@Test
func moduleRegistryRejectsDuplicateIDs() {
    let duplicate = NARCModule(
        id: "duplicate",
        displayName: "Duplicate",
        systemImageName: "square.stack",
        placements: [.panel],
        capabilities: [.browse],
        sortOrder: 100
    )

    do {
        _ = try ModuleRegistry(modules: [duplicate, duplicate])
        Issue.record("Expected duplicate module IDs to be rejected")
    } catch let error as ModuleRegistryError {
        #expect(error == .duplicateModuleID("duplicate"))
    } catch {
        Issue.record("Unexpected registry error: \(error)")
    }
}
