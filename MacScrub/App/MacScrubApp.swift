import SwiftUI

@main
struct MacScrubApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("MacScrub")
        } label: {
            Image(systemName: "sparkles")
        }
    }
}
