import SwiftUI

@main
struct CodexAppMobileApp: App {
    @StateObject private var store = ConnectionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
