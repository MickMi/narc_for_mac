import Testing
@testable import NARC

@Test
func onlyNotificationsSupportsLegacyPanelItemNavigation() {
    #expect(!PanelKeyboardRoute.inbox.supportsItemNavigation)
    #expect(PanelKeyboardRoute.notifications.supportsItemNavigation)
    #expect(!PanelKeyboardRoute.windows.supportsItemNavigation)
}

@Test
func inboxAndWindowsPassEditingAndNavigationKeysThrough() {
    let routedKeys: [UInt16] = [36, 126, 125, 48, 18]

    for route in [PanelKeyboardRoute.inbox, .windows] {
        for keyCode in routedKeys {
            #expect(
                route.decision(for: keyCode, isTextEditing: false) == .passThrough
            )
        }
    }

    #expect(
        PanelKeyboardRoute.notifications.decision(
            for: 36,
            isTextEditing: true
        ) == .passThrough
    )
    #expect(
        PanelKeyboardRoute.notifications.decision(
            for: 36,
            isTextEditing: false
        ) == .legacyItemNavigation
    )
}

@Test
func escapeDismissesEveryPanelRouteEvenWhileEditing() {
    for route in [PanelKeyboardRoute.inbox, .notifications, .windows] {
        #expect(
            route.decision(for: 53, isTextEditing: true) == .dismissPanel
        )
    }
}

@Test
@MainActor
func changingPanelRouteResetsLegacySelectionIntent() {
    let state = KeyboardSelectionState()
    state.route = .notifications
    state.selectedIndex = 3
    state.wantsKeyboardNavigation = true

    state.route = .inbox

    #expect(state.selectedIndex == -1)
    #expect(!state.wantsKeyboardNavigation)
}
