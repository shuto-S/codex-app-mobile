import SwiftUI

@main
struct CodexAppMobileApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(self.appState)
        }
    }
}
