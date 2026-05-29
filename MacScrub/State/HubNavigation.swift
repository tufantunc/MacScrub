import SwiftUI

enum HubView: Equatable {
    case main
    case preferences
}

/// Drives which view the main window shows (idle hub vs. preferences). One shared
/// instance is created by the app and injected into the window and the menu.
@MainActor
@Observable
final class HubNavigation {
    var view: HubView = .main
}
